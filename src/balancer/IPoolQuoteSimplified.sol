pragma solidity >=0.7.1;
pragma experimental ABIEncoderV2;

import "../interfaces/IERC20.sol";

interface IPoolQuoteStructs {
    // This is not really an interface - it just defines common structs used by other interfaces: IPoolQuote and
    // IPoolQuoteSimplified.

    // This data structure represents a request for a token swap, where the amount received by the Pool is known.
    //
    // `tokenIn` and `tokenOut` are the tokens the Pool will receive and send, respectively. `amountIn` is the number of
    // `tokenIn` tokens that the Pool will receive.
    //
    // All other fields are not strictly necessary for most swaps, but are provided to support advanced scenarios in
    // some Pools.
    // `poolId` is the ID of the Pool involved in the swap - this is useful for Pool contracts that implement more than
    // one Pool.
    // `from` is the origin address where funds the Pool receives are coming from, and `to` is the destination address
    // where the funds the Pool sends are going to.
    // `userData` is extra data provided by the caller - typically a signature from a trusted party.
    struct QuoteRequestGivenIn {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountIn;
        // Misc data
        bytes32 poolId;
        address from;
        address to;
        bytes userData;
    }

    // This data structure represents a request for a token swap, where the amount sent by the Pool is known.
    //
    // `tokenIn` and `tokenOut` are the tokens the Pool will receive and send, respectively. `amountOut` is the number
    // of `tokenOut` tokens that the Pool will send.
    //
    // All other fields are not strictly necessary for most swaps, but are provided to support advanced scenarios in
    // some Pools.
    // `poolId` is the ID of the Pool involved in the swap - this is useful for Pool contracts that implement more than
    // one Pool.
    // `from` is the origin address where funds the Pool receives are coming from, and `to` is the destination address
    // where the funds the Pool sends are going to.
    // `userData` is extra data provided by the caller - typically a signature from a trusted party.
    struct QuoteRequestGivenOut {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountOut;
        // Misc data
        bytes32 poolId;
        address from;
        address to;
        bytes userData;
    }
}

interface IPoolQuoteSimplified {
    function quoteOutGivenIn(
        IPoolQuoteStructs.QuoteRequestGivenIn calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) external returns (uint256 amountOut);

    function quoteInGivenOut(
        IPoolQuoteStructs.QuoteRequestGivenOut calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) external returns (uint256 amountIn);
}
