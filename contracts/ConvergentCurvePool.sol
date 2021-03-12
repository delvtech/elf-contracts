// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IERC20Decimals.sol";
import "./balancer-core-v2/lib/math/LogExpMath.sol";
import "./balancer-core-v2/lib/math/FixedPoint.sol";
import "./balancer-core-v2/vault/interfaces/IMinimalSwapInfoPool.sol";
import "./balancer-core-v2/vault/interfaces/IVault.sol";
import "./balancer-core-v2/pools/BalancerPoolToken.sol";

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

    // The fees recorded during swaps
    uint128 public feesUnderlying;
    uint128 public feesBond;
    // Stored records of governance tokens
    address public governance;
    // The percent of each trade's implied yield to collect as LP fee
    uint256 public immutable percentFee;
    // The percent of LP fees that is payed to governance
    uint256 public immutable percentFeeGov;

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
        string memory symbol
    ) BalancerPoolToken(name, symbol) {
        // Initialization on the vault
        bytes32 poolId = vault.registerPool(
            IVault.PoolSpecialization.TWO_TOKEN
        );

        // Pass in zero addresses for Asset Managers
        // Solidity really needs inline declaration of dynamic arrays
        // Note - functions below assume this token order
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = _underlying;
        tokens[1] = _bond;
        vault.registerTokens(poolId, tokens, new address[](2));

        // Set immutable state variables
        _vault = vault;
        _poolId = poolId;
        percentFee = _percentFee;
        percentFeeGov = _percentFeeGov;
        underlying = _underlying;
        underlyingDecimals = IERC20Decimals(address(_underlying)).decimals();
        bond = _bond;
        bondDecimals = IERC20Decimals(address(_bond)).decimals();
        expiration = _expiration;
        unitSeconds = _unitSeconds;
        governance = _governance;
    }

    // Balancer Interface required Getters

    /// @dev Returns the vault for this pool
    /// @return The vault for this pool
    function getVault() external override view returns (IVault) {
        return _vault;
    }

    /// @dev Returns the poolId for this pool
    /// @return The poolId for this pool
    function getPoolId() external override view returns (bytes32) {
        return _poolId;
    }

    // Trade Functionality

    /// @dev Returns the amount of 'tokenOut' to give for an input of 'tokenIn'
    /// @param request Balancer encoded structure with request details
    /// @param currentBalanceTokenIn The reserve of the input token
    /// @param currentBalanceTokenOut The reserve of the output token
    /// @return The amount of output token to send for the input token
    function onSwapGivenIn(
        IPoolSwapStructs.SwapRequestGivenIn calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) public override returns (uint256) {
        // Tokens amounts are passed to us in decimal form of the tokens
        uint256 amountTokenIn = request.amountIn;

        // We apply the trick which is used in the paper and
        // double count the reserves because the curve provisions liquidity
        // for prices above one underlying per bond, which we don't want to be accessible
        (uint256 tokenInReserve, uint256 tokenOutReserve) = _adjustedReserve(
            currentBalanceTokenIn,
            request.tokenIn,
            currentBalanceTokenOut,
            request.tokenOut
        );
        // Solve the invariant
        uint256 quote = solveTradeInvariant(
            amountTokenIn,
            tokenInReserve,
            tokenOutReserve,
            true
        );

        // Assign trade fees
        quote = _assignTradeFee(amountTokenIn, quote, request.tokenOut, false);
        return quote;
    }

    /// @dev Returns the amount of 'tokenIn' need to receive a specified amount
    ///      of 'tokenOut'
    /// @param request Balancer encoded structure with request details
    /// @param currentBalanceTokenIn The reserve of the input token
    /// @param currentBalanceTokenOut The reserve of the output token
    /// @return The amount of input token to receive the requested output
    function onSwapGivenOut(
        IPoolSwapStructs.SwapRequestGivenOut calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) public override returns (uint256) {
        // Tokens amounts are passed to us in decimal form of the tokens
        // However we want them to be in 18 decimal fixed point form
        uint256 amountTokenOut = request.amountOut;
        // We apply the trick which is used in the paper and
        // double count the reserves because the curve provisions liquidity
        // for prices above one underlying per bond, which we don't want to be accessible
        (uint256 tokenInReserve, uint256 tokenOutReserve) = _adjustedReserve(
            currentBalanceTokenIn,
            request.tokenIn,
            currentBalanceTokenOut,
            request.tokenOut
        );
        // Solve the invariant
        uint256 quote = solveTradeInvariant(
            amountTokenOut,
            tokenOutReserve,
            tokenInReserve,
            false
        );
        // Assign trade fees
        quote = _assignTradeFee(quote, amountTokenOut, request.tokenOut, true);
        return quote;
    }

    // Liquidity provider functionality

    /// @dev Hook for joining the pool that must be called from the vault.
    ///      It mints a proportional number of new tokens compared to current LP pool
    // @param poolId Unused by this pool but in interface
    // @param sender Unused by this pool but in interface
    /// @param recipient The address which will receive lp tokens.
    /// @param currentBalances The current pool balances, will be length 2
    // @param latestBlockNumberUsed Last block number, but not used in this pool
    /// @param protocolSwapFee The percent of pool fees to be paid to the Balancer Protocol
    /// @param userData Abi encoded fixed length 2 uint array containing:
    ///                 [max amount of underlying in, max amount of bond in]
    /// @return amountsIn The actual amounts of token the vault should move to this pool
    /// @return dueProtocolFeeAmounts The amounts of each token to pay as protocol fees
    function onJoinPool(
        bytes32, // poolId
        address, // sender
        address recipient,
        uint256[] calldata currentBalances,
        uint256,
        uint256 protocolSwapFee,
        bytes calldata userData
    )
        external
        override
        returns (
            uint256[] memory amountsIn,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        // Default checks
        require(msg.sender == address(_vault), "Non Vault caller");
        uint256[2] memory maxAmountsIn = abi.decode(userData, (uint256[2]));
        require(
            currentBalances.length == 2 && maxAmountsIn.length == 2,
            "Invalid format"
        );
        // Mint LP to the governance address.
        // The {} zoning here helps solidity figure out the stack
        {
            (
                uint256 localFeeUnderlying,
                uint256 localFeeBond
            ) = _mintGovernanceLP(currentBalances);
            dueProtocolFeeAmounts = new uint256[](2);
            dueProtocolFeeAmounts[0] = localFeeUnderlying.mul(protocolSwapFee);
            dueProtocolFeeAmounts[1] = localFeeBond.mul(protocolSwapFee);
        }
        // Mint for the user
        {
            (uint256 callerUsedUnderlying, uint256 callerUsedBond) = _mintLP(
                maxAmountsIn[0],
                maxAmountsIn[1],
                currentBalances,
                recipient
            );
            // Assign to variable memory arrays in return
            amountsIn = new uint256[](2);
            amountsIn[0] = callerUsedUnderlying;
            amountsIn[1] = callerUsedBond;
        }
    }

    /// @dev Hook for leaving the pool that must be called from the vault.
    ///      It burns a proportional number of tokens compared to current LP pool,
    ///      based on the minium output the user wants.
    // @param poolId Unused by this pool but in interface
    // @param sender Unused by this pool but in interface
    /// @param recipient The address which will receive lp tokens.
    /// @param currentBalances The current pool balances, will be length 2
    // @param latestBlockNumberUsed last block number unused in this pool
    /// @param protocolSwapFee The percent of pool fees to be paid to the Balancer Protocol
    /// @param userData Abi encoded fixed length 2 array containing
    ///                 [min output of underlying, min output of bond]
    /// @return amountsOut The number of each token to send to the caller
    /// @return dueProtocolFeeAmounts The amounts of each token to pay as protocol fees
    function onExitPool(
        bytes32,
        address,
        address recipient,
        uint256[] calldata currentBalances,
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
        uint256[2] memory minAmountsOut = abi.decode(userData, (uint256[2]));
        require(
            currentBalances.length == 2 && minAmountsOut.length == 2,
            "Invalid format"
        );
        // Mint LP to the governance address.
        // {} zones to help solidity figure out the stack
        {
            (
                uint256 localFeeUnderlying,
                uint256 localFeeBond
            ) = _mintGovernanceLP(currentBalances);

            dueProtocolFeeAmounts = new uint256[](2);
            dueProtocolFeeAmounts[0] = localFeeUnderlying.mul(protocolSwapFee);
            dueProtocolFeeAmounts[1] = localFeeBond.mul(protocolSwapFee);
        }
        // Burn for the user
        {
            (uint256 releasedUnderlying, uint256 releasedBond) = _burnLP(
                minAmountsOut[0],
                minAmountsOut[1],
                currentBalances,
                recipient
            );
            // Assign to variable memory arrays in return
            amountsOut = new uint256[](2);
            amountsOut[0] = releasedUnderlying;
            amountsOut[1] = releasedBond;
        }
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
        yAfter = LogExpMath.pow(yAfter, uint256(FixedPoint.ONE).div(a));
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
                uint256 impliedYieldFee = percentFee.mul(
                    amountOut.sub(amountIn)
                );
                // we record that fee collected from the underlying
                feesUnderlying += uint128(impliedYieldFee);
                // and return the adjusted input quote
                return amountIn.add(impliedYieldFee);
            } else {
                // If the input token is bond the implied yield is in - out
                uint256 impliedYieldFee = percentFee.mul(
                    amountIn.sub(amountOut)
                );
                // we record that collected fee from the input bond
                feesBond += uint128(impliedYieldFee);
                // and return the updated input quote
                return amountIn.add(impliedYieldFee);
            }
        } else {
            if (outputToken == bond) {
                // If the output is bond the implied yield is out - in
                uint256 impliedYieldFee = percentFee.mul(
                    amountOut.sub(amountIn)
                );
                // we record that fee collected from the bond output
                feesBond += uint128(impliedYieldFee);
                // and then return the updated output
                return amountOut.sub(impliedYieldFee);
            } else {
                // If the output is underlying the implied yield is in - out
                uint256 impliedYieldFee = percentFee.mul(
                    amountIn.sub(amountOut)
                );
                // we record the collected underlying fee
                feesUnderlying += uint128(impliedYieldFee);
                // and then return the updated output quote
                return amountOut.sub(impliedYieldFee);
            }
        }
        revert("Called with non pool token");
    }

    /// @dev Mints the maximum possible LP given a set of max inputs
    /// @param inputUnderlying The max underlying to deposit
    /// @param inputBond The max bond to deposit
    /// @param currentBalances The current balances encoded in a memory array
    /// @param recipient The person who receives the lp funds
    /// @return The actual amounts of token deposited layed out as (underlying, bond)
    function _mintLP(
        uint256 inputUnderlying,
        uint256 inputBond,
        uint256[] memory currentBalances,
        address recipient
    ) internal returns (uint256, uint256) {
        // Passing in in memory array helps stack but we use locals for better names
        uint256 reserveUnderlying = currentBalances[0];
        uint256 reserveBond = currentBalances[1];
        uint256 localTotalSupply = totalSupply();
        // Check if the pool is initialized
        if (localTotalSupply == 0) {
            // When uninitialized we mint exactly the underlying input
            // in LP tokens
            _mintPoolTokens(recipient, inputUnderlying);
            return (inputUnderlying, 0);
        }

        // Get the reserve ratio, the say how many underlying per bond in the reserve
        // (input underlying / reserve underlying) is the percent increase caused by deposit
        uint256 underlyingPerBond = reserveUnderlying.div(reserveBond);
        // Use the underlying per bond to get the needed number of input underlying
        uint256 neededUnderlying = underlyingPerBond.mul(inputBond);

        // If the user can't provide enough underlying
        if (neededUnderlying > inputUnderlying) {
            // The increase in total supply is the input underlying
            // as a ratio to reserve
            uint256 mintAmount = (inputUnderlying.mul(localTotalSupply)).div(
                reserveUnderlying
            );
            // We mint a new amount of as the the percent increase given
            // by the ratio of the input underlying to the reserve underlying
            _mintPoolTokens(recipient, mintAmount);
            // In this case we use the whole input of underlying
            // and consume (inputUnderlying/underlyingPerBond) bonds
            return (inputUnderlying, inputUnderlying.div(underlyingPerBond));
        } else {
            // We calculate the percent increase in the reserves from contributing
            // all of the bond
            uint256 mintAmount = (neededUnderlying.mul(localTotalSupply)).div(
                reserveUnderlying
            );
            // We then mint an amount of pool token which corresponds to that increase
            _mintPoolTokens(recipient, mintAmount);
            // The indicate we consumed the input bond and (inputBond*underlyingPerBond)
            return (neededUnderlying, inputBond);
        }
    }

    /// @dev Burns at least enough LP tokens from the sender to produce
    ///      as set of minium outputs.
    /// @param minOutputUnderlying The minimum output in underlying
    /// @param minOutputBond The minimum output in the bond
    /// @param currentBalances The current balances encoded in a memory array
    /// @param source The address to burn from.
    /// @return Tuple (output in underlying, output in bond)
    function _burnLP(
        uint256 minOutputUnderlying,
        uint256 minOutputBond,
        uint256[] memory currentBalances,
        address source
    ) internal returns (uint256, uint256) {
        // Passing in in memory array helps stack but we use locals for better names
        uint256 reserveUnderlying = currentBalances[0];
        uint256 reserveBond = currentBalances[1];
        uint256 localTotalSupply = totalSupply();
        // Calculate the ratio of the minOutputUnderlying to reserve
        uint256 underlyingPerBond = reserveUnderlying.div(reserveBond);
        // If the ratio won't produce enough bond
        if (minOutputUnderlying > minOutputBond.mul(underlyingPerBond)) {
            // In this case we burn enough tokens to output 'minOutputUnderlying'
            // which will be the total supply times the percent of the underlying
            // reserve which this amount of underlying is.
            uint256 burned = (minOutputUnderlying.mul(localTotalSupply)).div(
                reserveUnderlying
            );
            _burnPoolTokens(source, burned);
            // We return that we released 'minOutputUnderlying' and the number of bonds that
            // preserves the reserve ratio
            return (
                minOutputUnderlying,
                minOutputUnderlying.div(underlyingPerBond)
            );
        } else {
            // Then the amount burned is the ratio of the minOutputBond
            // to the reserve of bond times the total supply
            uint256 burned = (minOutputBond.mul(localTotalSupply)).div(
                reserveBond
            );
            _burnPoolTokens(source, burned);
            // We return that we released all of the minOutputBond
            // and the number of underlying which preserves the reserve ratio
            return (minOutputBond.mul(underlyingPerBond), minOutputBond);
        }
    }

    /// @dev Mints LP tokens from a percentage of the stored fees and then updates them
    /// @param currentBalances The reserve balances as [underlyingBalance, bondBalance]
    /// @return Returns the fee amounts as (feeUnderlying, feeBond) to avoid other sloads
    function _mintGovernanceLP(uint256[] memory currentBalances)
        internal
        returns (uint256, uint256)
    {
        // Load and cast the stored fees
        // Note - Because of sizes should only be one sload
        uint256 localFeeUnderlying = uint256(feesUnderlying);
        uint256 localFeeBond = uint256(feesBond);
        (uint256 feesUsedUnderlying, uint256 feesUsedBond) = _mintLP(
            localFeeUnderlying.mul(percentFeeGov),
            localFeeBond.mul(percentFeeGov),
            currentBalances,
            governance
        );
        // Safe math sanity checks
        require(
            localFeeUnderlying >= (feesUsedUnderlying).div(percentFeeGov),
            "Underflow"
        );
        require(localFeeBond >= (feesUsedBond).div(percentFeeGov), "Underflow");
        // Store the remaining fees should only be one sstore
        (feesUnderlying, feesBond) = (
            uint128(
                localFeeUnderlying - (feesUsedUnderlying).div(percentFeeGov)
            ),
            uint128(localFeeBond - (feesUsedBond).div(percentFeeGov))
        );
        // We return the sload-ed values so that they do not need to be loaded again.
        return (localFeeUnderlying, localFeeBond);
    }

    /// @dev Calculates 1 - t
    /// @return Returns 1 - t, encoded as a fraction in 18 decimal fixed point
    function _getYieldExponent() internal virtual view returns (uint256) {
        // The fractional time
        uint256 timeTillExpiry = block.timestamp < expiration
            ? expiration - block.timestamp
            : 0;
        timeTillExpiry *= 1e18;
        // timeTillExpiry now contains the a fixed point of the years remaining
        timeTillExpiry = timeTillExpiry.div(unitSeconds * 1e18);
        uint256 result = uint256(FixedPoint.ONE).sub(timeTillExpiry);
        return result;
    }

    /// @dev Applies the reserve adjustment from the paper and returns the reserves
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
}
