// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./IERC20Permit.sol";
import "./IERC20.sol";

interface IElf is IERC20Permit {
    function balance() external view returns (uint256);

    function balanceOfUnderlying(address who) external view returns (uint256);

    function getSharesToUnderlying(uint256 shares)
        external
        view
        returns (uint256);

    function setGovernance(address _governance) external;

    function setAllocator(address payable _allocator) external;

    function getAllocator() external view returns (address payable);

    function deposit(address sender, uint256 amount) external returns (uint256);

    function withdraw(address sender, uint256 _shares)
        external
        returns (uint256);
}
