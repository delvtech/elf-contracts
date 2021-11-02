// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface ICompoundVault is IERC20 {
    // mint?
    function deposit(uint256, address) external returns (uint256);

    // redeem?
    function withdraw(
        uint256,
        address,
        uint256
    ) external returns (uint256);

    // Returns the amount of underlying owned by `owner`
    function balanceOfUnderlying(address owner) external returns (uint256);

    function governance() external view returns (address);
}
