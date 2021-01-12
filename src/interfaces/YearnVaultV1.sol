// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

interface YearnVault {
    function earn() external;

    function deposit(uint256) external;

    function withdraw(uint256) external;

    function getPricePerFullShare() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);
}
