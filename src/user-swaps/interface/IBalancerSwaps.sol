pragma solidity >=0.5.8 <0.8.0;

interface IBalancerSwaps {
    function swapExactAmountIn(address, uint, address, uint, uint) external returns (uint, uint);
    function swapExactAmountOut(address, uint, address, uint, uint) external returns (uint, uint);
}
