pragma solidity >=0.5.8 <0.8.0;

interface IOracle {
    function getUnderlyingPrice(address) external view returns (uint);
}