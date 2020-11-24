// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.8 <0.8.0;

interface Aave {
    function deposit(
        address _reserve,
        uint256 _amount,
        uint16 _referralCode
    ) external payable;

    function borrow(
        address _reserve,
        uint256 _amount,
        uint256 _interestRateModel,
        uint16 _referralCode
    ) external;
}
