// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IWrappedPosition.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/ITrancheFactory.sol";
import "./interfaces/IInterestToken.sol";

import "./libraries/ERC20Permit.sol";
import "./libraries/DateString.sol";

/// @author Element Finance
/// @title Tranche
contract Tranche is ERC20Permit, ITranche {
    IInterestToken public immutable override interestToken;
    IWrappedPosition public immutable position;
    IERC20 public immutable override underlying;
    uint8 internal immutable _underlyingDecimals;

    // The outstanding amount of underlying which
    // can be redeemed from the contract from Principal Tokens
    // NOTE - we use smaller sizes so that they can be one storage slot
    uint128 public valueSupplied;
    // The total supply of interest tokens
    uint128 public override interestSupply;
    // The timestamp when tokens can be redeemed.
    uint256 public immutable override unlockTimestamp;
    // The amount of slippage allowed on the Principal token redemption [0.1 basis points]
    uint256 internal constant _SLIPPAGE_BP = 1e13;
    // The speedbump variable records the first timestamp where redemption was attempted to be
    // performed on a tranche where loss occurred. It blocks redemptions for 48 hours after
    // it is triggered in order to (1) prevent atomic flash loan price manipulation (2)
    // give 48 hours to remediate any other loss scenario before allowing withdraws
    uint256 public speedbump;
    // Const which is 48 hours in seconds
    uint256 internal constant _FORTY_EIGHT_HOURS = 172800;
    // An event to listen for when negative interest withdraw are triggered
    event SpeedBumpHit(uint256 timestamp);

    /// @notice Constructs this contract
    constructor() ERC20Permit("Element Principal Token ", "eP") {
        // Assume the caller is the Tranche factory.
        ITrancheFactory trancheFactory = ITrancheFactory(msg.sender);
        (
            address wpAddress,
            uint256 expiration,
            IInterestToken interestTokenTemp,
            // solhint-disable-next-line
            address unused
        ) = trancheFactory.getData();
        interestToken = interestTokenTemp;

        IWrappedPosition wpContract = IWrappedPosition(wpAddress);
        position = wpContract;

        // Store the immutable time variables
        unlockTimestamp = expiration;
        // We use local because immutables are not readable in construction
        IERC20 localUnderlying = wpContract.token();
        underlying = localUnderlying;
        // We load and store the underlying decimals
        uint8 localUnderlyingDecimals = localUnderlying.decimals();
        _underlyingDecimals = localUnderlyingDecimals;
        // And set this contract to have the same
        _setupDecimals(localUnderlyingDecimals);
    }

    /// @notice We override the optional extra construction function from ERC20 to change names
    function _extraConstruction() internal override {
        // Assume the caller is the Tranche factory and that this is called from constructor
        // We have to do this double load because of the lack of flexibility in constructor ordering
        ITrancheFactory trancheFactory = ITrancheFactory(msg.sender);
        (
            address wpAddress,
            uint256 expiration,
            // solhint-disable-next-line
            IInterestToken unused,
            address dateLib
        ) = trancheFactory.getData();

        string memory strategySymbol = IWrappedPosition(wpAddress).symbol();

        // Write the strategySymbol and expiration time to name and symbol

        // This logic was previously encoded as calling a library "DateString"
        // in line and directly. However even though this code is only in the constructor
        // it both made the code of this contract much bigger and made the factory
        // un deployable. So we needed to use the library as an external contract
        // but solidity does not have support for address to library conversions
        // or other support for working directly with libraries in a type safe way.
        // For that reason we have to use this ugly and non type safe hack to make these
        // contracts deployable. Since the library is an immutable in the factory
        // the security profile is quite similar to a standard external linked library.

        // We load the real storage slots of the symbol and name storage variables
        uint256 namePtr;
        uint256 symbolPtr;
        assembly {
            namePtr := name.slot
            symbolPtr := symbol.slot
        }
        // We then call the 'encodeAndWriteTimestamp' function on our library contract
        (bool success1, ) = dateLib.delegatecall(
            abi.encodeWithSelector(
                DateString.encodeAndWriteTimestamp.selector,
                strategySymbol,
                expiration,
                namePtr
            )
        );
        (bool success2, ) = dateLib.delegatecall(
            abi.encodeWithSelector(
                DateString.encodeAndWriteTimestamp.selector,
                strategySymbol,
                expiration,
                symbolPtr
            )
        );
        // Assert that both calls succeeded
        assert(success1 && success2);
    }

    /// @notice An aliasing of the getter for valueSupplied to improve ERC20 compatibility
    /// @return The number of principal tokens which exist.
    function totalSupply() external view returns (uint256) {
        return uint256(valueSupplied);
    }

    /**
    @notice Deposit wrapped position tokens and receive interest and Principal ERC20 tokens.
            If interest has already been accrued by the wrapped position
            tokens held in this contract, the number of Principal tokens minted is
            reduced in order to pay for the accrued interest.
    @param _amount The amount of underlying to deposit
    @param _destination The address to mint to
    @return The amount of principal and yield token minted as (pt, yt)
     */
    function deposit(uint256 _amount, address _destination)
        external
        override
        returns (uint256, uint256)
    {
        // Transfer the underlying to be wrapped into the position
        underlying.transferFrom(msg.sender, address(position), _amount);
        // Now that we have funded the deposit we can call
        // the prefunded deposit
        return prefundedDeposit(_destination);
    }

    /// @notice This function calls the prefunded deposit method to
    ///         create wrapped position tokens held by the contract. It should
    ///         only be called when a transfer has already been made to
    ///         the wrapped position contract of the underlying
    /// @param _destination The address to mint to
    /// @return the amount of principal and yield token minted as (pt, yt)
    /// @dev WARNING - The call which funds this method MUST be in the same transaction
    //                 as the call to this method or you risk loss of funds
    function prefundedDeposit(address _destination)
        public
        override
        returns (uint256, uint256)
    {
        // We check that this it is possible to deposit
        require(block.timestamp < unlockTimestamp, "expired");
        // Since the wrapped position contract holds a balance we use the prefunded deposit method
        (
            uint256 shares,
            uint256 usedUnderlying,
            uint256 balanceBefore
        ) = position.prefundedDeposit(address(this));
        // The implied current value of the holding of this contract in underlying
        // is the balanceBefore*(usedUnderlying/shares) since (usedUnderlying/shares)
        // is underlying per share and balanceBefore is the balance of this contract
        // in position tokens before this deposit.
        uint256 holdingsValue = (balanceBefore * usedUnderlying) / shares;
        // This formula is inputUnderlying - inputUnderlying*interestPerUnderlying
        // Accumulated interest has its value in the interest tokens so we have to mint less
        // principal tokens to account for that.
        // NOTE - If a pool has more than 100% interest in the period this will revert on underflow
        //        The user cannot discount the principal token enough to pay for the outstanding interest accrued.
        (uint256 _valueSupplied, uint256 _interestSupply) = (
            uint256(valueSupplied),
            uint256(interestSupply)
        );
        // We block deposits in negative interest rate regimes
        // The +2 allows for very small rounding errors which occur when
        // depositing into a tranche which is attached to a wp which has
        // accrued interest but the tranche has not yet accrued interest
        // and the first deposit into the tranche is substantially smaller
        // than following ones.
        require(_valueSupplied <= holdingsValue + 2, "E:NEG_INT");

        uint256 adjustedAmount;
        // Have to split on the initialization case and negative interest case
        if (_valueSupplied > 0 && holdingsValue > _valueSupplied) {
            adjustedAmount =
                usedUnderlying -
                ((holdingsValue - _valueSupplied) * usedUnderlying) /
                _interestSupply;
        } else {
            adjustedAmount = usedUnderlying;
        }
        // We record the new input of reclaimable underlying
        (valueSupplied, interestSupply) = (
            uint128(_valueSupplied + adjustedAmount),
            uint128(_interestSupply + usedUnderlying)
        );
        // We mint interest token for each underlying provided
        interestToken.mint(_destination, usedUnderlying);
        // We mint principal token discounted by the accumulated interest.
        _mint(_destination, adjustedAmount);
        // We return the number of principal token and yield token
        return (adjustedAmount, usedUnderlying);
    }

    /**
    @notice Burn principal tokens to withdraw underlying tokens.
    @param _amount The number of tokens to burn.
    @param _destination The address to send the underlying too
    @return The number of underlying tokens released
    @dev This method will return 1 underlying for 1 principal except when interest
         is negative, in which case the principal tokens is redeemable pro rata for
         the assets controlled by this vault.
         Also note: Redemption has the possibility of at most _SLIPPAGE_BP
         numerical error on each redemption so each principal token may occasionally redeem
         for less than 1 unit of underlying. Max loss defaults to 0.1 BP ie 0.001% loss
     */
    function withdrawPrincipal(uint256 _amount, address _destination)
        external
        override
        returns (uint256)
    {
        // No redemptions before unlock
        require(block.timestamp >= unlockTimestamp, "E:Not Expired");
        // If the speedbump == 0 it's never been hit so we don't need
        // to change the withdraw rate.
        uint256 localSpeedbump = speedbump;
        uint256 withdrawAmount = _amount;
        uint256 localSupply = uint256(valueSupplied);
        if (localSpeedbump != 0) {
            // Load the assets we have in this vault
            uint256 holdings = position.balanceOfUnderlying(address(this));
            // If we check and the interest rate is no longer negative then we
            // allow normal 1 to 1 withdraws [even if the speedbump was hit less
            // than 48 hours ago, to prevent possible griefing]
            if (holdings < localSupply) {
                // We allow the user to only withdraw their percent of holdings
                // NOTE - Because of the discounting mechanics this causes account loss
                //        percentages to be slightly perturbed from overall loss.
                //        ie: tokens holders who join when interest has accumulated
                //        will get slightly higher percent loss than those who joined earlier
                //        in the case of loss at the end of the period. Biases are very
                //        small except in extreme cases.
                withdrawAmount = (_amount * holdings) / localSupply;
                // If the interest rate is still negative and we are not 48 hours after
                // speedbump being set we revert
                require(
                    localSpeedbump + _FORTY_EIGHT_HOURS < block.timestamp,
                    "E:Early"
                );
            }
        }
        // Burn from the sender
        _burn(msg.sender, _amount);
        // Remove these principal token from the interest calculations for future interest redemptions
        valueSupplied = uint128(localSupply) - uint128(_amount);
        // Load the share balance of the vault before withdrawing [gas note - both the smart
        // contract and share value is warmed so this is actually quite a cheap lookup]
        uint256 shareBalanceBefore = position.balanceOf(address(this));
        // Calculate the min output
        uint256 minOutput = withdrawAmount -
            (withdrawAmount * _SLIPPAGE_BP) /
            1e18;
        // We make the actual withdraw from the position.
        (uint256 actualWithdraw, uint256 sharesBurned) = position
            .withdrawUnderlying(_destination, withdrawAmount, minOutput);

        // At this point we check that the implied contract holdings before this withdraw occurred
        // are more than enough to redeem all of the principal tokens for underlying ie that no
        // loss has happened.
        uint256 balanceBefore = (shareBalanceBefore * actualWithdraw) /
            sharesBurned;
        if (balanceBefore < localSupply) {
            // Require that that the speedbump has been set.
            require(localSpeedbump != 0, "E:NEG_INT");
            // This assert should be very difficult to hit because it is checked above
            // but may be possible with  complex reentrancy.
            assert(localSpeedbump + _FORTY_EIGHT_HOURS < block.timestamp);
        }
        return (actualWithdraw);
    }

    /// @notice This function allows someone to trigger the speedbump and eventually allow
    ///         pro rata withdraws
    function hitSpeedbump() external {
        // We only allow setting the speedbump once
        require(speedbump == 0, "E:AlreadySet");
        // We only allow setting it when withdraws can happen
        require(block.timestamp >= unlockTimestamp, "E:Not Expired");
        // We require that the total holds are less than the supply of
        // principal token we need to redeem
        uint256 totalHoldings = position.balanceOfUnderlying(address(this));
        if (totalHoldings < valueSupplied) {
            // We emit a notification so that if a speedbump is hit the community
            // can investigate.
            // Note - this is a form of defense mechanism because any flash loan
            //        attack must be public for at least 48 hours before it has
            //        affects.
            emit SpeedBumpHit(block.timestamp);
            // Set the speedbump
            speedbump = block.timestamp;
        } else {
            revert("E:NoLoss");
        }
    }

    /**
    @notice Burn interest tokens to withdraw underlying tokens.
    @param _amount The number of interest tokens to burn.
    @param _destination The address to send the result to
    @return The number of underlying token released
    @dev Due to slippage the redemption may receive up to _SLIPPAGE_BP less
         in output compared to the floating rate.
     */
    function withdrawInterest(uint256 _amount, address _destination)
        external
        override
        returns (uint256)
    {
        require(block.timestamp >= unlockTimestamp, "E:Not Expired");
        // Burn tokens from the sender
        interestToken.burn(msg.sender, _amount);
        // Load the underlying value of this contract
        uint256 underlyingValueLocked = position.balanceOfUnderlying(
            address(this)
        );
        // Load a stack variable to avoid future sloads
        (uint256 _valueSupplied, uint256 _interestSupply) = (
            uint256(valueSupplied),
            uint256(interestSupply)
        );
        // Interest is value locked minus current value
        uint256 interest = underlyingValueLocked > _valueSupplied
            ? underlyingValueLocked - _valueSupplied
            : 0;
        // The redemption amount is the interest per token times the amount
        uint256 redemptionAmount = (interest * _amount) / _interestSupply;
        uint256 minRedemption = redemptionAmount -
            (redemptionAmount * _SLIPPAGE_BP) /
            1e18;
        // Store that we reduced the supply
        interestSupply = uint128(_interestSupply - _amount);
        // Redeem position tokens for underlying
        (uint256 redemption, ) = position.withdrawUnderlying(
            _destination,
            redemptionAmount,
            minRedemption
        );
        return (redemption);
    }
}
