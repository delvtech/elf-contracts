pragma solidity ^0.6.2;

interface Converter {
    function convert(address _from, address _to, uint256 _amount, uint256 _conversionType) external;
}