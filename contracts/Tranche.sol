// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IElf.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/ITrancheFactory.sol";
import "./interfaces/IYC.sol";

import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/ERC20.sol";
import "./libraries/DateString.sol";

contract Tranche is ERC20, ITranche {
    using SafeERC20 for IERC20;
    using Address for address;

    IYC public immutable override yc;
    IElf public immutable elf;
    IERC20 public immutable underlying;
    uint8 immutable underlyingDecimals;

    // The outstanding amount of underlying which
    // can be redeemed from the contract from FYTs
    // NOTE - we use smaller sizes so that they can be one storage slot
    uint128 public valueSupplied;
    // The total supply of YCs
    uint128 public ycSupply;
    // The timestamp when FYTs and YCs can be redeemed.
    uint256 public immutable unlockTimestamp;
    // The amount of slippage allowed on the FYT redemption [0.1 basis points]
    uint256 constant SLIPPAGE_BP = 1e13;

    /// @notice Constructs this contract
    constructor() ERC20("Fixed Yield Token ", "FYT:") {
        // assume the caller is the Tranche factory.
        ITrancheFactory trancheFactory = ITrancheFactory(msg.sender);
        (address elfAddress, uint256 expiration, IYC ycTemp) = trancheFactory
            .getData();
        yc = ycTemp;

        IElf elfContract = IElf(elfAddress);
        elf = elfContract;

        string memory elfSymbol = elfContract.symbol();
        // Store the immutable time variables
        unlockTimestamp = expiration;
        // We use local because immutables are not readable in construction
        IERC20 localUnderlying = elfContract.token();
        underlying = elfContract.token();
        // We load and store the underlying decimals
        uint8 localUnderlyingDecimals = localUnderlying.decimals();
        underlyingDecimals = localUnderlyingDecimals;
        // And set this contract to have the same
        _setupDecimals(localUnderlyingDecimals);

        // Write the elfSymbol and expiration time to name and symbol
        DateString.encodeAndWriteTimestamp(elfSymbol, expiration, name);
        DateString.encodeAndWriteTimestamp(elfSymbol, expiration, symbol);
    }

    /**
    @notice Deposit ELF tokens and receive FYT and YC ERC20 tokens.
            If interest has already been accrued by the
            ELF tokens held in this contract, the number
            of FYT tokens minted is reduced in order to pay for the accrued interest.
    @param _amount The amount of underlying to deposit
    @param _destination The address to mint to
    @return The amount of FYT tokens minted after earned interest discount
     */
    function deposit(uint256 _amount, address _destination)
        external
        override
        returns (uint256)
    {
        // Tranfer the underlying into ELF
        underlying.transferFrom(msg.sender, address(elf), _amount);
        // Now that we have funded the deposit we can call
        // the prefunded deposit
        return prefundedDeposit(_destination);
    }

    /// @notice This function calls the prefunded deposit method to
    ///         create ELF token held by the contract. It should
    ///         only be called when a transfer has already been made to
    ///         the ELF of the underlying
    /// @param _destination The address to mint too
    function prefundedDeposit(address _destination)
        public
        override
        returns (uint256)
    {
        // We check that this it is possible to deposit
        require(block.timestamp < unlockTimestamp, "expired");
        // Since the ELF holds a balance we use the prefunded deposit method
        (uint256 shares, uint256 usedUnderlying, uint256 balanceBefore) = elf
            .prefundedDeposit(address(this));
        // The implied current value of the holding of this contract in underlying
        // is the balanceBefore*(usedUnderlying/shares) since (usedUnderlying/shares)
        // is underlying per share and balanceBefore is the balance of this contract
        // in ELF token before this deposit.
        uint256 holdingsValue = (balanceBefore * usedUnderlying) / shares;
        // This formula is inputUnderlying - inputUnderlying*interestPerUnderlying
        // Accumulated interest has its value in the YC so we have to mint less FYT
        // to account for that.
        // NOTE - If a pool has more than 100% interest in the period this will revert on underflow
        //        The user cannot discount the FYT enough to pay for the outstanding interest accrued.
        (uint256 _valueSupplied, uint256 _ycSupply) = (
            uint256(valueSupplied),
            uint256(ycSupply)
        );
        uint256 adjustedAmount;
        // Have to split on the initialization case
        if (_valueSupplied > 0) {
            adjustedAmount =
                2 *
                usedUnderlying -
                (usedUnderlying * holdingsValue) /
                _valueSupplied;
        } else {
            adjustedAmount = usedUnderlying;
        }
        // If negative interest has been accumulated we don't want to
        // give a bonus so we reset the amount to be exactly what was provided
        if (adjustedAmount > usedUnderlying) {
            adjustedAmount = usedUnderlying;
        }
        // We record the new input of reclaimable underlying
        (valueSupplied, ycSupply) = (
            uint128(_valueSupplied + adjustedAmount),
            uint128(_ycSupply + usedUnderlying)
        );
        // We mint YC for each underlying provided
        yc.mint(_destination, usedUnderlying);
        // We mint FYT discounted by the accumulated interest.
        _mint(_destination, adjustedAmount);
        // We return the number of FYT because it may be useful.
        return adjustedAmount;
    }

    /**
    @notice Burn FYT tokens to withdraw underlying tokens.
    @param _amount The number of FYT tokens to burn.
    @param _destination The address to send the underlying too
    @return The number of underlying tokens released
    @dev This method will return 1 underlying for 1 FYT except when interest
         is negative, in that case liquidity might run out and some FYT may
         not be redeemable. 
         Also note: FYT redemption has the possibility of at most SLIPPAGE_BP
         numerical error on each redemption so each FYT may occasionally redeem
         for less than 1 unit of underlying. It defaults to 0.1 BP ie 0.001% loss
     */
    function withdrawFyt(uint256 _amount, address _destination)
        external
        override
        returns (uint256)
    {
        // No redemptions before unlock
        require(block.timestamp >= unlockTimestamp, "not expired");
        // Burn from the sender
        _burn(msg.sender, _amount);
        // We normalize the FYT to the same units as the underlying
        uint256 amountUnderlying = (_amount * 10**underlyingDecimals) / 1e18;
        // Remove these FYT from the interest calculations for future YC redemptions
        valueSupplied -= uint128(amountUnderlying);
        uint256 minOutput = amountUnderlying -
            (amountUnderlying * SLIPPAGE_BP) /
            1e18;
        return
            elf.withdrawUnderlying(_destination, amountUnderlying, minOutput);
    }

    /**
    @notice Burn YC tokens to withdraw ELF tokens.
    @param _amount The number of YC tokens to burn.
    @param _destination The address to send the result to
    @return The number of underlying token released
    @dev Due to slippage the redemption may receive up to SLIPPAGE_BP less
         in output compared to the floating rate.
     */
    function withdrawYc(uint256 _amount, address _destination)
        external
        override
        returns (uint256)
    {
        require(block.timestamp >= unlockTimestamp, "not expired");
        // Burn tokens from the sender
        yc.burn(msg.sender, _amount);
        // Load the underlying value of this contract
        uint256 underlyingValueLocked = elf.balanceOfUnderlying(address(this));
        // Load a stack variable to avoid future sloads
        (uint256 _valueSupplied, uint256 _ycSupply) = (
            uint256(valueSupplied),
            uint256(ycSupply)
        );
        // Interest is value locked minus current value
        uint256 interest = underlyingValueLocked > _valueSupplied
            ? underlyingValueLocked - _valueSupplied
            : 0;
        // The redemption amount is the interest per YC times the amount
        uint256 redemptionAmount = (interest * _amount) / _ycSupply;
        uint256 minRedemption = redemptionAmount -
            (redemptionAmount * SLIPPAGE_BP) /
            1e18;
        // Store that we reduced the supply
        ycSupply = uint128(_ycSupply - _amount);
        // Redeem elf tokens for underlying
        return
            elf.withdrawUnderlying(
                _destination,
                redemptionAmount,
                minRedemption
            );
    }
}
