pragma solidity ^0.6.2;


interface Strategy {

    function allocateFunds(uint256) external;

    function deallocateFunds(uint256) external;

    function balanceOf() external view returns (uint256);
}