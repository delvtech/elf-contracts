pragma solidity >=0.5.8 <0.8.0;

contract AUserSwap {
    function swapExactAmountIn(
        address _tokenIn,
        uint _tokenAmountIn,
        address _tokenOut,
        uint _minAmountOut,
        uint _maxPrice
    ) external returns (uint, uint) {
        return (1, 1);
    }

    function swapExactAmountOut(
        address _tokenIn,
        uint _maxAmountIn,
        address _tokenOut,
        uint _tokenAmountOut,
        uint _maxPrice
    ) external returns (uint, uint) {
        return (1, 1);
    }
}
