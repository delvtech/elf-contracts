// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface YearnVault {
    function deposit(uint256) external returns (uint256);

    function withdraw(uint256) external returns (uint256);

    function getPricePerFullShare() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);
}
