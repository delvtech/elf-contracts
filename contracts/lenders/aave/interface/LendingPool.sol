pragma solidity ^0.6.2;

interface Aave {
    function deposit(address _reserve, uint256 _amount, uint16 _referralCode) external payable;
    function borrow(address _reserve, uint _amount, uint _interestRateModel, uint16 _referralCode) external;
}