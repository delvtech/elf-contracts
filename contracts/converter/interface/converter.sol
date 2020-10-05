pragma solidity >=0.4.22 <0.8.0;

interface Converter {
    function convert(address _from, address _to, uint256 _amount, uint256 _conversionType) external;
}