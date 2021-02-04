pragma solidity >=0.7.1;
pragma experimental ABIEncoderV2;

import "../interfaces/IERC20.sol";
import "./LogExpMath.sol";
import "./FixedPoint.sol";
import "./interfaces/IMinimalSwapInfoPoolQuote.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPool.sol";
import "./BalancerPoolToken.sol";

contract YieldCurvePool is IMinimalSwapInfoPoolQuote, BalancerPoolToken, IPool {
    using LogExpMath for uint256;
    using FixedPoint for uint256;

    // The token we expect to stay constant in value
    IERC20 public immutable underlying;
    uint8 public immutable underlyingDecimals;
    // The token we expect to appreciate to match underlying
    IERC20 public immutable bond;
    uint8 public immutable bondDecimals;
    // The time factor in fixed 18 decimal point
    int256 public immutable timeFactor;
    // The fee factor in fixed 18 decimal point
    uint256 public immutable feeFactor;
    // The expiration time
    uint256 public immutable expiration;
    // The number of seconds in a year
    uint256 public constant SECONDS_IN_YEAR = 31536000;
    // The Balancer pool data
    // Note we change style to match Balancer's custom getter
    IVault private immutable _vault;
    bytes32 private immutable _poolId;

    // The fees recorded during swaps
    uint128 public feesUnderlying;
    uint128 public feesBond;
    // Stored records of governance tokens
    address public governance;
    // The percent of accumulated fees to pay to the vault.
    uint256 public immutable percentFee;

    /// @dev We need need to set the immutables on contract creation
    ///      Note - We expect both 'bond' and 'underlying' to have 'decimals()'
    /// @param _underlying The asset which the second asset should appreciate to match
    /// @param _bond The asset which should be appreciating
    /// @param _timeFactor A multiplier on the time differential used for setting curvature.
    /// @param _feeFactor A multiplier for setting fee rates, g in the yield paper
    /// @param _expiration The time in unix seconds when the bond asset should equal the underlying asset
    constructor(
        IERC20 _underlying,
        IERC20 _bond,
        int256 _timeFactor,
        uint256 _feeFactor,
        uint256 _expiration,
        IVault vault,
        uint256 _percentFee,
        string memory name,
        string memory symbol
    ) BalancerPoolToken(name, symbol) {
        // Initialization on the vault
        bytes32 poolId = vault.registerPool(IVault.PoolSpecialization.GENERAL);

        // Pass in zero addresses for Asset Managers
        // Solidity really needs inline declaration of dynamic arrays
        // Note - functions below assume this token order
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = _underlying;
        tokens[1] = _bond;
        vault.registerTokens(poolId, tokens, new address[](0));

        // Set immutable state variables
        _vault = vault;
        _poolId = poolId;
        percentFee = _percentFee;
        underlying = _underlying;
        underlyingDecimals = _underlying.decimals();
        bond = _bond;
        bondDecimals = _bond.decimals();
        timeFactor = _timeFactor;
        feeFactor = _feeFactor;
        expiration = _expiration;
    }

    // Balancer Interface required Getters

    /// @dev Returns the vault for this pool
    /// @return the vault for this pool
    function getVault() external override view returns (IVault) {
        return _vault;
    }

    /// @dev Returns the poolId for this pool
    /// @return the poolId for this pool
    function getPoolId() external override view returns (bytes32) {
        return _poolId;
    }

    // Trade Functionality

    /// @dev Returns the amount of 'tokenOut' to give for an input of 'tokenIn'
    /// @param request balancer encoded structure with request details
    /// @param currentBalanceTokenIn the reserve of the input token
    /// @param currentBalanceTokenOut the reserve of the output token
    /// @return The amount of output token to send for the input token
    function quoteOutGivenIn(
        IPoolQuoteStructs.QuoteRequestGivenIn calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) external override returns (uint256) {
        // Tokens amounts are passed to us in decimal form of the tokens
        // However we
        uint256 amountTokenIn = _tokenToFixed(
            request.amountIn,
            request.tokenIn
        );
        currentBalanceTokenIn = _tokenToFixed(
            currentBalanceTokenIn,
            request.tokenIn
        );
        currentBalanceTokenOut = _tokenToFixed(
            currentBalanceTokenOut,
            request.tokenOut
        );
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
        quote = _assignTradeFee(quote, request.amountIn, request.tokenOut);

        // TODO - Do we need to enforce that the pool doesn't provide prices such that
        // bond/underlying > 1?
        // Return the quote to token form
        return _fixedToToken(quote, request.tokenOut);
    }

    /// @dev Returns the amount of 'tokenIn' need to receive a specified amount
    ///      of 'tokenOut'
    /// @param request balancer encoded structure with request details
    /// @param currentBalanceTokenIn the reserve of the input token
    /// @param currentBalanceTokenOut the reserve of the output token
    /// @return The amount of input token to receive the requested output
    function quoteInGivenOut(
        IPoolQuoteStructs.QuoteRequestGivenOut calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) external override returns (uint256) {
        // Tokens amounts are passed to us in decimal form of the tokens
        // However we want them to be in 18 decimal fixed point form
        uint256 amountTokenOut = _tokenToFixed(
            request.amountOut,
            request.tokenIn
        );
        currentBalanceTokenIn = _tokenToFixed(
            currentBalanceTokenIn,
            request.tokenIn
        );
        currentBalanceTokenOut = _tokenToFixed(
            currentBalanceTokenOut,
            request.tokenOut
        );
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
            tokenInReserve,
            tokenOutReserve,
            false
        );
        // Assign trade fees
        quote = _assignTradeFee(quote, request.amountOut, request.tokenIn);
        // Return the quote in input token decimals
        // TODO - Do we need to enforce that the pool doesn't provide prices such that
        // bond/underlying > 1?
        return _fixedToToken(quote, request.tokenIn);
    }

    // Liquidity provider functionality

    /// @dev Hook for joining the pool that must be called from the vault.
    ///      It mints a proportional number of new tokens compared to current LP pool
    // @param poolId Unused by this pool but in interface
    // @param sender Unused by this pool but in interface
    /// @param recipient The address which will receive lp tokens.
    /// @param currentBalances The current pool balances, will be length 2
    /// @param maxAmountsIn The max amount each token transferable in this mint
    /// @param protocolSwapFee The percent of pool fees to be paid to the Balancer Protocol
    // @param userData Unused by this pool but in interface
    /// @return amountsIn The actual amounts of token the vault should move to this pool
    /// @return dueProtocolFeeAmounts The amounts of each token to pay as protocol fees
    function onJoinPool(
        bytes32,
        address,
        address recipient,
        uint256[] calldata currentBalances,
        uint256[] calldata maxAmountsIn,
        uint256 protocolSwapFee,
        bytes calldata
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
    /// @param minAmountsOut The minium outputs the user wants
    /// @param protocolSwapFee The percent of pool fees to be paid to the Balancer Protocol
    // @param userData Unused by this pool but in interface
    /// @return amountsOut The number of each token to send to the caller
    /// @return dueProtocolFeeAmounts The amounts of each token to pay as protocol fees
    function onExitPool(
        bytes32,
        address,
        address recipient,
        uint256[] calldata currentBalances,
        uint256[] calldata minAmountsOut,
        uint256 protocolSwapFee,
        bytes calldata
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
        // Mint for the user
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
    /// @param amountX the amount of token x sent in normalized to have 18 decimals
    /// @param reserveX the amount of the token x currently held by the pool normalized to 18 decimals
    /// @param reserveY the amount of the token y currently held by the pool normalized to 18 decimals
    /// @param out is true if the pool will receive amountX and false if it is expected to produce it.
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
        uint256 xBeforePowA = reserveX.pow(a);
        // calculate y before ^ a
        uint256 yBeforePowA = reserveY.pow(a);
        // calculate x after ^ a
        uint256 xAfterPowA = out
            ? (reserveX + amountX).pow(a)
            : (reserveX.sub(amountX)).pow(a);
        // Calculate y_after = ( x_before ^a + y_ before ^a -  x_after^a)^(1/a)
        // Will revert with underflow here if the liquidity isn't enough for the trade
        // TODO - Consider a specified error message.
        uint256 yAfter = (xBeforePowA + yBeforePowA).sub(xAfterPowA);
        // Note that this call is to FixedPoint Div so works as intended
        yAfter = yAfter.pow(uint256(FixedPoint.ONE).div(a));
        // The amount of Y token to send is (reserveY_before - reserveY_after)
        // TODO - Consider adding a small edge to account for numerical error
        return out ? reserveY.sub(yAfter) : yAfter.sub(reserveY);
    }

    /// @dev Adds a fee equal to to 'feePercent' of remaining interest to each trade
    ///      This function is overloaded between output quotes and input quotes.
    ///      If the trade is quoting an amount out for a fixed amount in, token should
    ///      be the out token. If the trade is quoting an amount input for a fixed output
    ///      the token should be the input token.
    /// @param quote The amount quoted by the invariant.
    /// @param amount The 18 point encoded fixed amount
    /// @param quoteToken The token of the quote
    /// @return The updated output quote
    //  Note - The safe math in this function implicitly prevents the price of 'bond' in underlying
    //         from being higher than 1.
    function _assignTradeFee(
        uint256 quote,
        uint256 amount,
        IERC20 quoteToken
    ) internal returns (uint256) {
        // The math splits on if this is a buy or a sell
        if (quoteToken == bond) {
            // The amount of underlying is per bond is (underlying in)/(bonds out)
            uint256 pricePerBond = amount.div(quote);
            // This price implies a yield of 1 - price, and we assign a per bond fee of 'percentFee'
            uint256 impliedYieldFee = (
                uint256(FixedPoint.ONE).sub(pricePerBond)
            )
                .mul(percentFee);
            // We generate a new quote by diving the amount in by an increased price
            uint256 newQuote = amount.div(pricePerBond.add(impliedYieldFee));
            // We record the amount of fees collected in bond
            feesBond += uint128(quote.sub(newQuote));
            // And return the new quote
            quote = newQuote;
        } else {
            // The underlying per bond is the output underlying divided by the amount out
            uint256 pricePerBond = quote.div(amount);
            // The price implied a yield which we take a precent of and hold on a unit basis
            uint256 impliedYieldFee = (
                uint256(FixedPoint.ONE).sub(pricePerBond)
            )
                .mul(percentFee);
            // We update the quote by reducing the amount of underlying this trade generates
            quote = amount.mul(pricePerBond.sub(impliedYieldFee));
            // We then add the amount of underlying the fee prevented from sending out to the fees.
            feesUnderlying += uint128(amount.mul(impliedYieldFee));
        }
        return quote;
    }

    /// @dev Mints the maximum possible LP given a set of max inputs
    /// @param inputUnderlying The max underlying to deposit
    /// @param inputBond The max bond to deposit
    /// @param currentBalances The current balances encoded in a memory array
    /// @param recipient the person who receives the lp funds
    /// @return the actual amounts of token deposited layed out as (underlying, bond)
    function _mintLP(
        uint256 inputUnderlying,
        uint256 inputBond,
        uint256[] memory currentBalances,
        address recipient
    ) internal returns (uint256, uint256) {
        // Passing in in memory array helps stack but we use locals for better names
        uint256 reserveUnderlying = currentBalances[0];
        uint256 reserveBond = currentBalances[1];
        // Get the ratio of the max input of underlying to the reserves
        uint256 ratio = inputUnderlying.div(reserveUnderlying);
        // Get the amount of bond implied by that ratio
        uint256 neededBond = ratio.mul(reserveBond);

        if (neededBond > inputBond) {
            // If we would need more bond in  we reduce the ratio
            // by getting the ratio of bondIn to bondReserve
            ratio = inputBond.div(reserveBond);
            // We mint that ratio
            _mintPoolTokens(recipient, ratio.mul(totalSupply()));
            // We take as deposit that ratio times the underlying reserve
            return (reserveUnderlying.mul(ratio), inputBond);
        } else {
            // In this case we have enough input bond to cover needed bond
            // So we  mint the increased ratio of total supply
            _mintPoolTokens(recipient, ratio.mul(totalSupply()));
            // The indicate we consumed the input underlying and neededBond
            return (inputUnderlying, neededBond);
        }
    }

    /// @dev Burns at least enough LP tokens from the sender to produce
    ///      as set of minium outputs.
    /// @param minOutputUnderlying The minimum output in underlying
    /// @param minOutputBond The minimum output in the bond
    /// @param currentBalances The current balances encoded in a memory array
    /// @param source The address to burn from.
    /// @return returns (output in underlying, output in bond)
    function _burnLP(
        uint256 minOutputUnderlying,
        uint256 minOutputBond,
        uint256[] memory currentBalances,
        address source
    ) internal returns (uint256, uint256) {
        // Passing in in memory array helps stack but we use locals for better names
        uint256 reserveUnderlying = currentBalances[0];
        uint256 reserveBond = currentBalances[1];
        // Calculate the ratio of the minOutputUnderlying to reserve
        uint256 ratio = minOutputUnderlying.div(reserveUnderlying);
        // If the ratio won't produce enough bond
        if (reserveBond.mul(ratio) > minOutputBond) {
            // Then we need to reset it to the bond output
            ratio = minOutputBond.div(reserveBond);
            // As a math note reserveBond*(minOutputUnderlying/reserveUnderlying) > minOutputBond
            // implies that reserveUnderlying*(minOutputBond/reserveBond) > minOutputUnderlying
        }
        // We now burn the ratio of the total supply freed by the caller
        _burnPoolTokens(source, ratio.mul(totalSupply()));
        // We return outputs
        return (ratio.mul(reserveUnderlying), ratio.mul(reserveBond));
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
            localFeeUnderlying.mul(percentFee),
            localFeeBond.mul(percentFee),
            currentBalances,
            governance
        );
        // Store the remaining fees should only be one sstore
        // TODO - Check on gas limit handling to see if storing 1 will reduce the
        // the estimates for this function and the trade.
        (feesUnderlying, feesBond) = (
            uint128(localFeeUnderlying - feesUsedUnderlying),
            uint128(localFeeBond - feesUsedBond)
        );
        return (localFeeUnderlying, localFeeBond);
    }

    /// @dev Calculates 1 - t
    /// @return Returns 1 - t, encoded as a fraction in 18 decimal fixed point
    function _getYieldExponent() internal view returns (uint256) {
        // The fractional time
        uint256 timeTillExpiry = block.timestamp < expiration
            ? expiration - block.timestamp
            : 0;
        timeTillExpiry *= 1e18;
        // timeTillExpiry now contains the a fixed point of the years remaining
        timeTillExpiry /= SECONDS_IN_YEAR;
        return uint256(FixedPoint.ONE).sub(timeTillExpiry);
    }

    /// @dev Applies the reserve adjustment from the paper and returns the reserves
    /// @param reserveTokenIn the reserve of the input token
    /// @param tokenIn the address of the input token
    /// @param reserveTokenOut the reserve of the output token
    /// @return returns (adjustedReserveIn, adjustedReserveOut)
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

    /// @dev Turns a token which is either 'bond' or 'underlying' into 18 point decimal
    /// @param amount the amount of the token in native decimal encoding
    /// @param token the address of the token
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
    /// @param amount the amount of the token in 18 point fixed point
    /// @param token the address of the token
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
    /// @param amount the amount to normalize
    /// @param decimalsBefore the decimal encoding before
    /// @param decimalsAfter the decimal encoding after
    function _normalize(
        uint256 amount,
        uint8 decimalsBefore,
        uint8 decimalsAfter
    ) internal pure returns (uint256) {
        // If we need to increase the decimals
        if (decimalsBefore > decimalsAfter) {
            // Then we shift right the amount by the number of decimals
            amount = amount >> (decimalsBefore - decimalsAfter);
            // If we need to decrease the number
        } else if (decimalsBefore < decimalsAfter) {
            // then we shift left by the difference
            amount = amount << (decimalsAfter - decimalsBefore);
        }
        // If nothing changed this is a no-op
        return amount;
    }
}
