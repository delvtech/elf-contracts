pragma solidity >=0.5.8 <0.8.0;

import "./interface/IBalancerSwaps.sol";

contract ElementUserSwaps {
    address public BPOOL;

    constructor(address _bPool) public {
        BPOOL = _bPool;
    }
    
    function swapExactAmountIn(
        address _tokenIn,
        uint _tokenAmountIn,
        address _tokenOut,
        uint _minAmountOut,
        uint _maxPrice
    ) external returns (uint, uint) {
        return IBalancerSwaps(BPOOL).swapExactAmountIn(_tokenIn, _tokenAmountIn, _tokenOut, _minAmountOut, _maxPrice);
    }

    function swapExactAmountOut(
        address _tokenIn,
        uint _maxAmountIn,
        address _tokenOut,
        uint _tokenAmountOut,
        uint _maxPrice
    ) external returns (uint, uint) {
        return IBalancerSwaps(BPOOL).swapExactAmountOut(_tokenIn, _maxAmountIn, _tokenOut, _tokenAmountOut, _maxPrice);
    }
}
