pragma solidity >=0.4.22 <0.8.0;

interface Aave {
    function deposit(address _reserve, uint256 _amount, uint16 _referralCode) external payable;
    function borrow(address _reserve, uint _amount, uint _interestRateModel, uint16 _referralCode) external;
}