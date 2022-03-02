// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./interfaces/IERC20Decimals.sol";
import "./balancer-core-v2/lib/math/LogExpMath.sol";
import "./balancer-core-v2/lib/math/FixedPoint.sol";
import "./balancer-core-v2/vault/interfaces/IMinimalSwapInfoPool.sol";
import "./balancer-core-v2/vault/interfaces/IVault.sol";
import "./balancer-core-v2/pools/BalancerPoolToken.sol";

// SECURITY - A governance address can freeze trading and deposits but has no access to user funds
//            and cannot stop withdraws.

contract ConvergentCurvePool is IMinimalSwapInfoPool, BalancerPoolToken {
    using LogExpMath for uint256;
    using FixedPoint for uint256;

    // The token we expect to stay constant in value
    IERC20 public immutable underlying;
    uint8 public immutable underlyingDecimals;
    // The token we expect to appreciate to match underlying
    IERC20 public immutable bond;
    uint8 public immutable bondDecimals;
    // The expiration time
    uint256 public immutable expiration;
    // The number of seconds in our timescale
    uint256 public immutable unitSeconds;
    // The Balancer pool data
    // Note we change style to match Balancer's custom getter
    IVault private immutable _vault;
    bytes32 private immutable _poolId;

    // The fees recorded during swaps, this is the total fees collected by LPs on all trades.
    // These will be 18 point not token decimal encoded
    uint120 public feesUnderlying;
    uint120 public feesBond;
    // A bool to indicate if the contract is paused, stored with 'fees bond'
    bool public paused;
    // The fees which have been allocated to pay governance, a percent of LP fees on trades
    // Since we don't have access to transfer they must be stored so governance can collect them later
    uint128 public governanceFeesUnderlying;
    uint128 public governanceFeesBond;
    // A mapping of who can pause
    mapping(address => bool) public pausers;
    // Stored records of governance tokens
    address public immutable governance;
    // The percent of each trade's implied yield to collect as LP fee
    uint256 public immutable percentFee;
    // The percent of LP fees that is payed to governance
    uint256 public immutable percentFeeGov;

    // Store constant token indexes for ascending sorted order
    // In this case despite these being internal it's cleaner
    // to ignore linting rules that require _
    /* solhint-disable private-vars-leading-underscore */
    uint256 internal immutable baseIndex;
    uint256 internal immutable bondIndex;
    /* solhint-enable private-vars-leading-underscore */

    // The max percent fee for governance, immutable after compilation
    uint256 public constant FEE_BOUND = 3e17;

    // State saying if the contract is paused

    /// @notice This event allows the frontend to track the fees
    /// @param collectedBase the base asset tokens fees collected in this txn
    /// @param collectedBond the bond asset tokens fees collected in this txn
    /// @param remainingBase the amount of base asset fees have been charged but not collected
    /// @param remainingBond the amount of bond asset fees have been charged but not collected
    /// @dev All values emitted by this event are 18 point fixed not token native decimals
    event FeeCollection(
        uint256 collectedBase,
        uint256 collectedBond,
        uint256 remainingBase,
        uint256 remainingBond
    );

    /// @dev We need need to set the immutables on contract creation
    ///      Note - We expect both 'bond' and 'underlying' to have 'decimals()'
    /// @param _underlying The asset which the second asset should appreciate to match
    /// @param _bond The asset which should be appreciating
    /// @param _expiration The time in unix seconds when the bond asset should equal the underlying asset
    /// @param _unitSeconds The number of seconds in a unit of time, for example 1 year in seconds
    /// @param vault The balancer vault
    /// @param _percentFee The percent each trade's yield to collect as fees
    /// @param _percentFeeGov The percent of collected that go to governance
    /// @param _governance The address which gets minted reward lp
    /// @param name The balancer pool token name
    /// @param symbol The balancer pool token symbol
    /// @param _pauser An address that can pause trades and deposits
    constructor(
        IERC20 _underlying,
        IERC20 _bond,
        uint256 _expiration,
        uint256 _unitSeconds,
        IVault vault,
        uint256 _percentFee,
        uint256 _percentFeeGov,
        address _governance,
        string memory name,
        string memory symbol,
        address _pauser
    ) BalancerPoolToken(name, symbol) {
        // Sanity Check
        require(_expiration - block.timestamp < _unitSeconds);
        // Initialization on the vault
        bytes32 poolId = vault.registerPool(
            IVault.PoolSpecialization.TWO_TOKEN
        );

        IERC20[] memory tokens = new IERC20[](2);
        if (_underlying < _bond) {
            tokens[0] = _underlying;
            tokens[1] = _bond;
        } else {
            tokens[0] = _bond;
            tokens[1] = _underlying;
        }

        // Set that the _pauser can pause
        pausers[_pauser] = true;

        // Pass in zero addresses for Asset Managers
        // Note - functions below assume this token order
        vault.registerTokens(poolId, tokens, new address[](2));

        // Set immutable state variables
        _vault = vault;
        _poolId = poolId;
        percentFee = _percentFee;
        // We check that the gov percent fee is less than bound
        require(_percentFeeGov < FEE_BOUND, "Fee too high");
        percentFeeGov = _percentFeeGov;
        underlying = _underlying;
        underlyingDecimals = IERC20Decimals(address(_underlying)).decimals();
        bond = _bond;
        bondDecimals = IERC20Decimals(address(_bond)).decimals();
        expiration = _expiration;
        unitSeconds = _unitSeconds;
        governance = _governance;
        // Calculate the preset indexes for ordering
        bool underlyingFirst = _underlying < _bond;
        baseIndex = underlyingFirst ? 0 : 1;
        bondIndex = underlyingFirst ? 1 : 0;
    }

    // Balancer Interface required Getters

    /// @dev Returns the vault for this pool
    /// @return The vault for this pool
    function getVault() external view returns (IVault) {
        return _vault;
    }

    /// @dev Returns the poolId for this pool
    /// @return The poolId for this pool
    function getPoolId() external view returns (bytes32) {
        return _poolId;
    }

    // Trade Functionality

    /// @dev Called by the Vault on swaps to get a price quote
    /// @param swapRequest The request which contains the details of the swap
    /// @param currentBalanceTokenIn The input token balance
    /// @param currentBalanceTokenOut The output token balance
    /// @return the amount of the output or input token amount of for swap
    function onSwap(
        SwapRequest memory swapRequest,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) public override notPaused returns (uint256) {
        // Check that the sender is pool, we change state so must make
        // this check.
        require(msg.sender == address(_vault), "Non Vault caller");
        // Tokens amounts are passed to us in decimal form of the tokens
        // But we want theme in 18 point
        uint256 amount;
        bool isOutputSwap = swapRequest.kind == IVault.SwapKind.GIVEN_IN;
        if (isOutputSwap) {
            amount = _tokenToFixed(swapRequest.amount, swapRequest.tokenIn);
        } else {
            amount = _tokenToFixed(swapRequest.amount, swapRequest.tokenOut);
        }
        currentBalanceTokenIn = _tokenToFixed(
            currentBalanceTokenIn,
            swapRequest.tokenIn
        );
        currentBalanceTokenOut = _tokenToFixed(
            currentBalanceTokenOut,
            swapRequest.tokenOut
        );

        // We apply the trick which is used in the paper and
        // double count the reserves because the curve provisions liquidity
        // for prices above one underlying per bond, which we don't want to be accessible
        (uint256 tokenInReserve, uint256 tokenOutReserve) = _adjustedReserve(
            currentBalanceTokenIn,
            swapRequest.tokenIn,
            currentBalanceTokenOut,
            swapRequest.tokenOut
        );

        // We switch on if this is an input or output case
        if (isOutputSwap) {
            // We get quote
            uint256 quote = solveTradeInvariant(
                amount,
                tokenInReserve,
                tokenOutReserve,
                isOutputSwap
            );
            // We assign the trade fee
            quote = _assignTradeFee(amount, quote, swapRequest.tokenOut, false);
            // We return the quote
            return _fixedToToken(quote, swapRequest.tokenOut);
        } else {
            // We get the quote
            uint256 quote = solveTradeInvariant(
                amount,
                tokenOutReserve,
                tokenInReserve,
                isOutputSwap
            );
            // We assign the trade fee
            quote = _assignTradeFee(quote, amount, swapRequest.tokenOut, true);
            // We return the output
            return _fixedToToken(quote, swapRequest.tokenIn);
        }
    }

    /// @dev Hook for joining the pool that must be called from the vault.
    ///      It mints a proportional number of tokens compared to current LP pool,
    ///      based on the maximum input the user indicates.
    /// @param poolId The balancer pool id, checked to ensure non erroneous vault call
    // @param sender Unused by this pool but in interface
    /// @param recipient The address which will receive lp tokens.
    /// @param currentBalances The current pool balances, sorted by address low to high.  length 2
    // @param latestBlockNumberUsed last block number unused in this pool
    /// @param protocolSwapFee no fee is collected on join only when they are paid to governance
    /// @param userData Abi encoded fixed length 2 array containing max inputs also sorted by
    ///                 address low to high
    /// @return amountsIn The actual amounts of token the vault should move to this pool
    /// @return dueProtocolFeeAmounts The amounts of each token to pay as protocol fees
    function onJoinPool(
        bytes32 poolId,
        address, // sender
        address recipient,
        uint256[] memory currentBalances,
        uint256,
        uint256 protocolSwapFee,
        bytes calldata userData
    )
        external
        override
        notPaused
        returns (
            uint256[] memory amountsIn,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        // Default checks
        require(msg.sender == address(_vault), "Non Vault caller");
        require(poolId == _poolId, "Wrong pool id");
        uint256[] memory maxAmountsIn = abi.decode(userData, (uint256[]));
        require(
            currentBalances.length == 2 && maxAmountsIn.length == 2,
            "Invalid format"
        );
        require(
            recipient != governance,
            "Governance address LP would be locked"
        );
        // We must normalize the inputs to 18 point
        _normalizeSortedArray(currentBalances);
        _normalizeSortedArray(maxAmountsIn);

        // This (1) removes governance fees and balancer fees which are collected but not paid
        // from the current balances (2) adds any to be collected gov fees to state (3) calculates
        // the fees to be paid to balancer on this call.
        dueProtocolFeeAmounts = _feeAccounting(
            currentBalances,
            protocolSwapFee
        );

        // Mint for the user
        amountsIn = _mintLP(
            maxAmountsIn[baseIndex],
            maxAmountsIn[bondIndex],
            currentBalances,
            recipient
        );

        // We now have make the outputs have the correct decimals
        _denormalizeSortedArray(amountsIn);
        _denormalizeSortedArray(dueProtocolFeeAmounts);
    }

    /// @dev Hook for leaving the pool that must be called from the vault.
    ///      It burns a proportional number of tokens compared to current LP pool,
    ///      based on the minium output the user wants.
    /// @param poolId The balancer pool id, checked to ensure non erroneous vault call
    /// @param sender The address which is the source of the LP token
    // @param recipient Unused by this pool but in interface
    /// @param currentBalances The current pool balances, sorted by address low to high.  length 2
    // @param latestBlockNumberUsed last block number unused in this pool
    /// @param protocolSwapFee The percent of pool fees to be paid to the Balancer Protocol
    /// @param userData Abi encoded uint256 which is the number of LP tokens the user wants to
    ///                 withdraw
    /// @return amountsOut The number of each token to send to the caller
    /// @return dueProtocolFeeAmounts The amounts of each token to pay as protocol fees
    function onExitPool(
        bytes32 poolId,
        address sender,
        address,
        uint256[] memory currentBalances,
        uint256,
        uint256 protocolSwapFee,
        bytes calldata userData
    )
        external
        override
        returns (
            uint256[] memory amountsOut,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        // Default checks
        require(msg.sender == address(_vault), "Non Vault caller");
        require(poolId == _poolId, "Wrong pool id");
        uint256 lpOut = abi.decode(userData, (uint256));

        // We have to convert to 18 decimals
        _normalizeSortedArray(currentBalances);

        // This (1) removes governance fees and balancer fees which are collected but not paid
        // from the current balances (2) adds any to be collected gov fees to state (3) calculates
        // the fees to be paid to balancer on this call.
        dueProtocolFeeAmounts = _feeAccounting(
            currentBalances,
            protocolSwapFee
        );

        // If governance is withdrawing they can get all of the fees
        if (sender == governance) {
            // Init the array
            amountsOut = new uint256[](2);
            // Governance withdraws the fees which have been paid to them
            amountsOut[baseIndex] = uint256(governanceFeesUnderlying);
            amountsOut[bondIndex] = uint256(governanceFeesBond);
            // We now have to zero the governance fees
            governanceFeesUnderlying = 0;
            governanceFeesBond = 0;
        } else {
            // Calculate the user's proportion of the reserves
            amountsOut = _burnLP(lpOut, currentBalances, sender);
        }

        // We need to convert the balancer outputs to token decimals instead of 18
        _denormalizeSortedArray(amountsOut);
        _denormalizeSortedArray(dueProtocolFeeAmounts);
        return (amountsOut, dueProtocolFeeAmounts);
    }

    /// @dev Returns the balances so that they'll be in the order [underlying, bond].
    /// @param currentBalances balances sorted low to high of address value.
    function _getSortedBalances(uint256[] memory currentBalances)
        internal
        view
        returns (uint256 underlyingBalance, uint256 bondBalance)
    {
        return (currentBalances[baseIndex], currentBalances[bondIndex]);
    }

    /// @dev Turns an array of token amounts into an array of 18 point amounts
    /// @param data The data to normalize
    function _normalizeSortedArray(uint256[] memory data) internal view {
        data[baseIndex] = _normalize(data[baseIndex], underlyingDecimals, 18);
        data[bondIndex] = _normalize(data[bondIndex], bondDecimals, 18);
    }

    /// @dev Turns an array of 18 point amounts into token amounts
    /// @param data The data to turn in to token decimals
    function _denormalizeSortedArray(uint256[] memory data) internal view {
        data[baseIndex] = _normalize(data[baseIndex], 18, underlyingDecimals);
        data[bondIndex] = _normalize(data[bondIndex], 18, bondDecimals);
    }

    // Permission-ed functions

    /// @notice checks for a pause on trading and depositing functionality
    modifier notPaused() {
        require(!paused, "Paused");
        _;
    }

    /// @notice Allows an authorized address or the owner to pause this contract
    /// @param pauseStatus true for paused, false for not paused
    /// @dev the caller must be authorized
    function pause(bool pauseStatus) external {
        require(pausers[msg.sender], "Sender not Authorized");
        paused = pauseStatus;
    }

    /// @notice Governance sets someone's pause status
    /// @param who The address
    /// @param status true for able to pause false for not
    function setPauser(address who, bool status) external {
        require(msg.sender == governance, "Sender not Owner");
        pausers[who] = status;
    }

    // Math libraries and internal routing

    /// @dev Calculates how many tokens should be outputted given an input plus reserve variables
    ///      Assumes all inputs are in 18 point fixed compatible with the balancer fixed math lib.
    ///      Since solving for an input is almost exactly the same as an output you can indicate
    ///      if this is an input or output calculation in the call.
    /// @param amountX The amount of token x sent in normalized to have 18 decimals
    /// @param reserveX The amount of the token x currently held by the pool normalized to 18 decimals
    /// @param reserveY The amount of the token y currently held by the pool normalized to 18 decimals
    /// @param out Is true if the pool will receive amountX and false if it is expected to produce it.
    /// @return Either if 'out' is true the amount of Y token to send to the user or
    ///         if 'out' is false the amount of Y Token to take from the user
    function solveTradeInvariant(
        uint256 amountX,
        uint256 reserveX,
        uint256 reserveY,
        bool out
    ) public view returns (uint256) {
        // Gets 1 - t
        uint256 a = _getYieldExponent();
        // calculate x before ^ a
        uint256 xBeforePowA = LogExpMath.pow(reserveX, a);
        // calculate y before ^ a
        uint256 yBeforePowA = LogExpMath.pow(reserveY, a);
        // calculate x after ^ a
        uint256 xAfterPowA = out
            ? LogExpMath.pow(reserveX + amountX, a)
            : LogExpMath.pow(reserveX.sub(amountX), a);
        // Calculate y_after = ( x_before ^a + y_ before ^a -  x_after^a)^(1/a)
        // Will revert with underflow here if the liquidity isn't enough for the trade
        uint256 yAfter = (xBeforePowA + yBeforePowA).sub(xAfterPowA);
        // Note that this call is to FixedPoint Div so works as intended
        yAfter = LogExpMath.pow(yAfter, uint256(FixedPoint.ONE).divDown(a));
        // The amount of Y token to send is (reserveY_before - reserveY_after)
        return out ? reserveY.sub(yAfter) : yAfter.sub(reserveY);
    }

    /// @dev Adds a fee equal to to 'feePercent' of remaining interest to each trade
    ///      This function accepts both input and output trades, amd expects that all
    ///      inputs are in fixed 18 point
    /// @param amountIn The trade's amountIn in fixed 18 point
    /// @param amountOut The trade's amountOut in fixed 18 point
    /// @param outputToken The output token
    /// @param isInputTrade True if the trader is requesting a quote for the amount of input
    ///                     they need to provide to get 'amountOut' false otherwise
    /// @return The updated output quote
    //  Note - The safe math in this function implicitly prevents the price of 'bond' in underlying
    //         from being higher than 1.
    function _assignTradeFee(
        uint256 amountIn,
        uint256 amountOut,
        IERC20 outputToken,
        bool isInputTrade
    ) internal returns (uint256) {
        // The math splits on if this is input or output
        if (isInputTrade) {
            // Then it splits again on which token is the bond
            if (outputToken == bond) {
                // If the output is bond the implied yield is out - in
                uint256 impliedYieldFee = percentFee.mulDown(
                    amountOut.sub(amountIn)
                );
                // we record that fee collected from the underlying
                feesUnderlying += uint120(impliedYieldFee);
                // and return the adjusted input quote
                return amountIn.add(impliedYieldFee);
            } else {
                // If the input token is bond the implied yield is in - out
                uint256 impliedYieldFee = percentFee.mulDown(
                    amountIn.sub(amountOut)
                );
                // we record that collected fee from the input bond
                feesBond += uint120(impliedYieldFee);
                // and return the updated input quote
                return amountIn.add(impliedYieldFee);
            }
        } else {
            if (outputToken == bond) {
                // If the output is bond the implied yield is out - in
                uint256 impliedYieldFee = percentFee.mulDown(
                    amountOut.sub(amountIn)
                );
                // we record that fee collected from the bond output
                feesBond += uint120(impliedYieldFee);
                // and then return the updated output
                return amountOut.sub(impliedYieldFee);
            } else {
                // If the output is underlying the implied yield is in - out
                uint256 impliedYieldFee = percentFee.mulDown(
                    amountIn.sub(amountOut)
                );
                // we record the collected underlying fee
                feesUnderlying += uint120(impliedYieldFee);
                // and then return the updated output quote
                return amountOut.sub(impliedYieldFee);
            }
        }
    }

    /// @dev Mints the maximum possible LP given a set of max inputs
    /// @param inputUnderlying The max underlying to deposit
    /// @param inputBond The max bond to deposit
    /// @param currentBalances The current pool balances, sorted by address low to high.  length 2
    /// @param recipient The person who receives the lp funds
    /// @return amountsIn The actual amounts of token deposited in token sorted order
    function _mintLP(
        uint256 inputUnderlying,
        uint256 inputBond,
        uint256[] memory currentBalances,
        address recipient
    ) internal returns (uint256[] memory amountsIn) {
        // Initialize the memory array with length
        amountsIn = new uint256[](2);
        // Passing in in memory array helps stack but we use locals for better names
        (uint256 reserveUnderlying, uint256 reserveBond) = _getSortedBalances(
            currentBalances
        );

        uint256 localTotalSupply = totalSupply();
        // Check if the pool is initialized
        if (localTotalSupply == 0) {
            // When uninitialized we mint exactly the underlying input
            // in LP tokens
            _mintPoolTokens(recipient, inputUnderlying);
            // Return the right data
            amountsIn[baseIndex] = inputUnderlying;
            amountsIn[bondIndex] = 0;
            return (amountsIn);
        }
        // Get the reserve ratio, the say how many underlying per bond in the reserve
        // (input underlying / reserve underlying) is the percent increase caused by deposit
        uint256 underlyingPerBond = reserveUnderlying.divDown(reserveBond);
        // Use the underlying per bond to get the needed number of input underlying
        uint256 neededUnderlying = underlyingPerBond.mulDown(inputBond);

        // If the user can't provide enough underlying
        if (neededUnderlying > inputUnderlying) {
            // The increase in total supply is the input underlying
            // as a ratio to reserve
            uint256 mintAmount = (inputUnderlying.mulDown(localTotalSupply))
                .divDown(reserveUnderlying);
            // We mint a new amount of as the the percent increase given
            // by the ratio of the input underlying to the reserve underlying
            _mintPoolTokens(recipient, mintAmount);
            // In this case we use the whole input of underlying
            // and consume (inputUnderlying/underlyingPerBond) bonds
            amountsIn[baseIndex] = inputUnderlying;
            amountsIn[bondIndex] = inputUnderlying.divDown(underlyingPerBond);
        } else {
            // We calculate the percent increase in the reserves from contributing
            // all of the bond
            uint256 mintAmount = (neededUnderlying.mulDown(localTotalSupply))
                .divDown(reserveUnderlying);
            // We then mint an amount of pool token which corresponds to that increase
            _mintPoolTokens(recipient, mintAmount);
            // The indicate we consumed the input bond and (inputBond*underlyingPerBond)
            amountsIn[baseIndex] = neededUnderlying;
            amountsIn[bondIndex] = inputBond;
        }
    }

    /// @dev Burns a number of LP tokens and returns the amount of the pool which they own.
    /// @param lpOut The minimum output in underlying
    /// @param currentBalances The current pool balances, sorted by address low to high.  length 2
    /// @param source The address to burn from.
    /// @return amountsReleased in address sorted order
    function _burnLP(
        uint256 lpOut,
        uint256[] memory currentBalances,
        address source
    ) internal returns (uint256[] memory amountsReleased) {
        // Load the number of LP token
        uint256 localTotalSupply = totalSupply();
        // Burn the LP tokens from the user
        _burnPoolTokens(source, lpOut);
        // Initialize the memory array with length 2
        amountsReleased = new uint256[](2);
        // They get a percent ratio of the pool, div down will cause a very small
        // rounding error loss.
        amountsReleased[baseIndex] = (currentBalances[baseIndex].mulDown(lpOut))
            .divDown(localTotalSupply);
        amountsReleased[bondIndex] = (currentBalances[bondIndex].mulDown(lpOut))
            .divDown(localTotalSupply);
    }

    /// @dev Calculates 1 - t
    /// @return Returns 1 - t, encoded as a fraction in 18 decimal fixed point
    function _getYieldExponent() internal view virtual returns (uint256) {
        // The fractional time
        uint256 timeTillExpiry = block.timestamp < expiration
            ? expiration - block.timestamp
            : 0;
        timeTillExpiry *= 1e18;
        // timeTillExpiry now contains the a fixed point of the years remaining
        timeTillExpiry = timeTillExpiry.divDown(unitSeconds * 1e18);
        uint256 result = uint256(FixedPoint.ONE).sub(timeTillExpiry);
        // Sanity Check
        require(result != 0);
        // Return result
        return result;
    }

    /// @dev Applies the reserve adjustment from the paper and returns the reserves
    ///      Note: The inputs should be in 18 point fixed to match the LP decimals
    /// @param reserveTokenIn The reserve of the input token
    /// @param tokenIn The address of the input token
    /// @param reserveTokenOut The reserve of the output token
    /// @return Returns (adjustedReserveIn, adjustedReserveOut)
    function _adjustedReserve(
        uint256 reserveTokenIn,
        IERC20 tokenIn,
        uint256 reserveTokenOut,
        IERC20 tokenOut
    ) internal view returns (uint256, uint256) {
        // We need to identify the bond asset and the underlying
        // This check is slightly redundant in most cases but more secure
        if (tokenIn == underlying && tokenOut == bond) {
            // We return (underlyingReserve, bondReserve + totalLP)
            return (reserveTokenIn, reserveTokenOut + totalSupply());
        } else if (tokenIn == bond && tokenOut == underlying) {
            // We return (bondReserve + totalLP, underlyingReserve)
            return (reserveTokenIn + totalSupply(), reserveTokenOut);
        }
        // This should never be hit
        revert("Token request doesn't match stored");
    }

    /// @notice Mutates the input current balances array to remove fees paid to governance and balancer
    ///         Also resets the LP storage and realizes governance fees, returns the fees which are paid
    ///         to balancer
    /// @param currentBalances The overall balances
    /// @param balancerFee The percent of LP fees that balancer takes as a fee
    /// @return dueProtocolFees The fees which will be paid to balancer on this join or exit
    /// @dev WARNING - Solidity will implicitly cast a 'uint256[] calldata' to 'uint256[] memory' on function calls, but
    ///                since calldata is immutable mutations made in this call are discarded in future references to the
    ///                variable in other functions. 'currentBalances' must STRICTLY be of type uint256[] memory for this
    ///                function to work.
    function _feeAccounting(
        uint256[] memory currentBalances,
        uint256 balancerFee
    ) internal returns (uint256[] memory dueProtocolFees) {
        // Load the total fees
        uint256 localFeeUnderlying = uint256(feesUnderlying);
        uint256 localFeeBond = uint256(feesBond);
        dueProtocolFees = new uint256[](2);
        // Calculate the balancer fee [this also implicitly returns this data]
        dueProtocolFees[baseIndex] = localFeeUnderlying.mulDown(balancerFee);
        dueProtocolFees[bondIndex] = localFeeBond.mulDown(balancerFee);
        //  Calculate the governance fee from total LP
        uint256 govFeeBase = localFeeUnderlying.mulDown(percentFeeGov);
        uint256 govFeeBond = localFeeBond.mulDown(percentFeeGov);
        // Add the fees collected by gov to the stored ones
        governanceFeesUnderlying += uint128(govFeeBase);
        governanceFeesBond += uint128(govFeeBond);
        // We subtract the amounts which are paid as fee but have not been collected.
        // This leaves LPs with the deposits plus their amount of fees
        currentBalances[baseIndex] = currentBalances[baseIndex]
            .sub(dueProtocolFees[baseIndex])
            .sub(governanceFeesUnderlying);
        currentBalances[bondIndex] = currentBalances[bondIndex]
            .sub(dueProtocolFees[bondIndex])
            .sub(governanceFeesBond);
        // Since all fees have been accounted for we reset the LP fees collected to zero
        feesUnderlying = uint120(0);
        feesBond = uint120(0);
    }

    /// @dev Turns a token which is either 'bond' or 'underlying' into 18 point decimal
    /// @param amount The amount of the token in native decimal encoding
    /// @param token The address of the token
    /// @return The amount of token encoded into 18 point fixed point
    function _tokenToFixed(uint256 amount, IERC20 token)
        internal
        view
        returns (uint256)
    {
        // In both cases we are targeting 18 point
        if (token == underlying) {
            return _normalize(amount, underlyingDecimals, 18);
        } else if (token == bond) {
            return _normalize(amount, bondDecimals, 18);
        }
        // Should never happen
        revert("Called with non pool token");
    }

    /// @dev Turns an 18 fixed point amount into a token amount
    ///       Token must be either 'bond' or 'underlying'
    /// @param amount The amount of the token in 18 decimal fixed point
    /// @param token The address of the token
    /// @return The amount of token encoded in native decimal point
    function _fixedToToken(uint256 amount, IERC20 token)
        internal
        view
        returns (uint256)
    {
        if (token == underlying) {
            // Recodes to 'underlyingDecimals' decimals
            return _normalize(amount, 18, underlyingDecimals);
        } else if (token == bond) {
            // Recodes to 'bondDecimals' decimals
            return _normalize(amount, 18, bondDecimals);
        }
        // Should never happen
        revert("Called with non pool token");
    }

    /// @dev Takes an 'amount' encoded with 'decimalsBefore' decimals and
    ///      re encodes it with 'decimalsAfter' decimals
    /// @param amount The amount to normalize
    /// @param decimalsBefore The decimal encoding before
    /// @param decimalsAfter The decimal encoding after
    function _normalize(
        uint256 amount,
        uint8 decimalsBefore,
        uint8 decimalsAfter
    ) internal pure returns (uint256) {
        // If we need to increase the decimals
        if (decimalsBefore > decimalsAfter) {
            // Then we shift right the amount by the number of decimals
            amount = amount / 10**(decimalsBefore - decimalsAfter);
            // If we need to decrease the number
        } else if (decimalsBefore < decimalsAfter) {
            // then we shift left by the difference
            amount = amount * 10**(decimalsAfter - decimalsBefore);
        }
        // If nothing changed this is a no-op
        return amount;
    }
}
