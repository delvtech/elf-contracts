pragma solidity >=0.7.1;
pragma experimental ABIEncoderV2;

import "../interfaces/IERC20.sol";
import "./LogExpMath.sol";
import "./FixedPoint.sol";
import "./IPoolQuoteSimplified.sol";


contract YieldCurvePool is IPoolQuoteSimplified {
    
    using LogExpMath for uint256;
    using FixedPoint for uint256;
    
    // The token we expect to stay constant in value
    IERC20 immutable underlying;
    uint8 immutable underlying_decimals;
    // The token we expect to appreciate to match underlying
    IERC20 immutable bond;
    uint8 immutable bond_decimals;
    // The time factor in fixed 18 decimal point
    int256 immutable time_factor;
    // The fee factor in fixed 18 decimal point
    uint256 immutable fee_factor;
    // The expiration time
    uint256 immutable expiration;
    // The number of seconds in a year
    uint256 constant SECONDS_IN_YEAR = 31536000;
    // The totalSupply of lp tokens
    uint256 lpTotalSupply;
    
    /// @dev We need need to set the immutables on contract creation
    ///      Note - We expect both 'bond' and 'underlying' to have 'decimals()'
    /// @param _underlying The asset which the second asset should appreciate to match
    /// @param _bond The asset which should be appreciating
    /// @param _time_factor A multiplier on the time differential used for setting curvature.
    /// @param _fee_factor A multiplier for setting fee rates, g in the yield paper
    /// @param _expiration The time in unix seconds when the bond asset should equal the underlying asset
    constructor(IERC20 _underlying, IERC20 _bond, int256 _time_factor, uint256 _fee_factor, uint256 _expiration) {
        underlying = _underlying;
        underlying_decimals = _underlying.decimals();
        bond = _bond;
        bond_decimals = _bond.decimals();
        time_factor = _time_factor;
        fee_factor = _fee_factor;
        expiration = _expiration;
    }
    
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
        uint256 amountTokenIn = tokenToFixed(request.amountIn, request.tokenIn);
        currentBalanceTokenIn = tokenToFixed(currentBalanceTokenIn, request.tokenIn);
        currentBalanceTokenOut = tokenToFixed(currentBalanceTokenOut, request.tokenOut);
        // We apply the trick which is used in the paper and
        // double count the reserves because the curve provisions liquidity
        // for prices above one underlying per bond, which we don't want to be accessible
        (uint256 tokenInReserve, uint256 tokenOutReserve) = adjustedReserve(currentBalanceTokenIn, request.tokenIn, currentBalanceTokenOut, request.tokenOut);
        // Solve the invariant
        uint256 quote = solveInvariant(amountTokenIn, tokenInReserve, tokenOutReserve, true);
        // TODO - Do we need to enforce that the pool doesn't provide prices such that
        // bond/underlying > 1?
        // Return the quote to token form
        return fixedToToken(quote, request.tokenOut);
    }

    /// @dev Returns the amount of 'tokenIn' need to receive a specified amount
    ///      of 'tokenOut'
    /// @param request balancer encoded structure with request details
    /// @param currentBalanceTokenIn the reserve of the input token
    /// @param currentBalanceTokenOut the reserve of the output token
    /// @return The amount of input token to receive amountOut
    function quoteInGivenOut(
        IPoolQuoteStructs.QuoteRequestGivenOut calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) external override returns (uint256 amountIn) {
        // Tokens amounts are passed to us in decimal form of the tokens
        // However we want them to be in 18 decimal fixed point form
        uint256 amountTokenOut = tokenToFixed(request.amountOut, request.tokenIn);
        currentBalanceTokenIn = tokenToFixed(currentBalanceTokenIn, request.tokenIn);
        currentBalanceTokenOut = tokenToFixed(currentBalanceTokenOut, request.tokenOut);
        // We apply the trick which is used in the paper and
        // double count the reserves because the curve provisions liquidity
        // for prices above one underlying per bond, which we don't want to be accessible
        (uint256 tokenInReserve, uint256 tokenOutReserve) = adjustedReserve(currentBalanceTokenIn, request.tokenIn, currentBalanceTokenOut, request.tokenOut);
        // Solve the invariant
        uint256 quote = solveInvariant(amountTokenOut, tokenInReserve, tokenOutReserve, false);
        // Return the quote in input token decimals
        // TODO - Do we need to enforce that the pool doesn't provide prices such that
        // bond/underlying > 1?
        return fixedToToken(quote, request.tokenIn);
    }
    
    /// @dev Calculates how many tokens should be outputted given an input plus reserve variables
    ///      Assumes all inputs are in 18 point fixed compatible with the balancer fixed math lib.
    ///      Invariant x_before ^(1-t/g) + y_ before ^(1-t/g) = x_after^(1 - t/g) + y_after^(1 - t/g)
    ///      Since solving for an input is almost exactly the same as an output you can indicate
    ///      if this is an input or output calculation in the call.
    /// @param amountX the amount of token x sent in normalized to have 18 decimals
    /// @param reserveX the amount of the token x currently held by the pool normalized to 18 decimals
    /// @param reserveY the amount of the token y currently held by the pool normalized to 18 decimals
    /// @param out is true if the pool will receive amountX and false if it is expected to produce it.
    /// @return Either if 'out' is true the amount of Y token to send to the user or
    ///         if 'out' is false the amount of Y Token to take from the user
    function solveInvariant(uint256 amountX, uint256 reserveX, uint256 reserveY, bool out) public view returns(uint256) {
        // Gets 1 - t/g
        uint256 a = getYieldExponent();
        // calculate x before ^ (1 - t/g)
        uint256 xBeforePowA = reserveX.pow(a);
        // calculate y before ^ (1 - t/g)
        uint256 yBeforePowA = reserveY.pow(a);
        // calculate x after ^ (1 - t/g)
        uint256 xAfterPowA = out?(reserveX + amountX).pow(a): (reserveX.sub(amountX)).pow(a);
        // Calculate y_after = ( x_before ^(1-t/g) + y_ before ^(1-t/g) -  x_after^(1 - t/g))^(1/(1-t/g))
        // Will revert with underflow here if the liqudity isn't enough for the trade
        // TODO - Consider a specified error message.
        uint256 yAfter = (xBeforePowA + yBeforePowA).sub(xAfterPowA);
        // Note that this call is to FixedPoint Div so works as intended
        yAfter = yAfter.pow(uint256(FixedPoint.ONE).div(a));
        // The amount of Y token to send is (reserveY_before - reserveY_after)
        // TODO - Consider adding a small edge to account for numerical error
        return out? reserveY.sub(yAfter): yAfter.sub(reserveY);
    }
    
    /// @dev Calculates 1 - t/g from the paper
    /// @return Returns 1 - t/g encoded as a fraction in 18 decimal fixed point
    function getYieldExponent() internal view returns(uint256) {
        // Holding var for 1 - t/g
        uint256 timeTillExpiry = block.timestamp < expiration? expiration - block.timestamp: 0;
        timeTillExpiry *= 1e18;
        // timeTillExpiry now contains the a fixed point of the years remaining
        timeTillExpiry /= SECONDS_IN_YEAR;
        // We multiply by the fixed point time multiplier
        timeTillExpiry = timeTillExpiry.mul(fee_factor);
        // 1 - t/g
        return uint256(FixedPoint.ONE).sub(timeTillExpiry.div(fee_factor));
    }
    
    /// @dev Applies the reserve adjustment from the paper and returns the reserves
    /// @param reserveTokenIn the reserve of the input token
    /// @param tokenIn the address of the input token
    /// @param reserveTokenOut the reserve of the output token
    /// @return returns (adjustedReserveIn, adjustedReserveOut)
    function adjustedReserve(uint256 reserveTokenIn, IERC20 tokenIn, uint256 reserveTokenOut, IERC20 tokenOut) internal view returns (uint256, uint256) {
        // We need to identify the bond asset and the underlying
        // This check is slightly redundant in most cases but more secure 
        if (tokenIn == underlying && tokenOut == bond) {
            // We return (underlyingReserve, bondReserve + totalLP)
            return (reserveTokenIn, reserveTokenOut + lpTotalSupply);
        } else if (tokenIn == bond && tokenOut == underlying) {
            // We return (bondReserve + totalLP, underlyingReserve)
            return (reserveTokenIn + lpTotalSupply, reserveTokenOut);
        }
        // This should never be hit
        revert("Token request dosen't match stored");
    }
    
    /// @dev Turns a token which is either 'bond' or 'underlying' into 18 point decimal
    /// @param amount the amount of the token in native decimal encoding
    /// @param token the address of the token
    /// @return The amount of token encoded into 18 point fixed point
    function tokenToFixed(uint256 amount, IERC20 token) internal view returns (uint256) {
        // In both cases we are targeting 18 point
        if (token == underlying) {
            return normalize(amount, underlying_decimals, 18);
        } else if (token == bond) {
            return normalize(amount, bond_decimals, 18);
        }
        // Should never happen
        revert("Called with non pool token");
    }
    
    /// @dev Turns an 18 fixed point amount into a token amount
    ///       Token must be either 'bond' or 'underlying'
    /// @param amount the amount of the token in 18 point fixed point
    /// @param token the address of the token
    /// @return The amount of token encoded in native decimal point
    function fixedToToken(uint256 amount, IERC20 token) internal view returns(uint256) {
        if (token == underlying) {
            // Recodes to 'underlying_decimals' decimals
            return normalize(amount, 18, underlying_decimals);
        } else if (token == bond) {
            // Recodes to 'bond_decimals' decimals
            return normalize(amount, 18, bond_decimals);
        }
        // Should never happen
        revert("Called with non pool token");
    }
    
    /// @dev Takes an 'amount' encoded with 'decimals_before' decimals and 
    ///      rencodes it with 'decimals_after' decimals
    function normalize(uint256 amount, uint8 decimals_before, uint8 decimals_after) internal pure returns (uint256) {
        // If we need to increase the decimals
        if (decimals_before > decimals_after){
            // Then we shift right the amount by the number of decimals
            amount = amount >> (decimals_before - decimals_after); 
        // If we need to decrease the number
        } else if (decimals_before < decimals_after) {
            // then we shift left by the difference
            amount = amount << (decimals_after - decimals_before);
        }
        // If nothing changed this is a no-op
        return amount;
    }
}