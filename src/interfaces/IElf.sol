// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./IERC20Permit.sol";
import "./IERC20.sol";

interface IElf is IERC20Permit, IERC20 {
    function balance() external view returns (uint256);

    function balanceOfUnderlying(address who) external view returns (uint256);

    function getSharesToUnderlying(uint256 shares)
        external
        view
        returns (uint256);

    function setGovernance(address _governance) external;

    function setAllocator(address payable _allocator) external;

    function getAllocator() external view returns (address payable);

    function deposit(uint256 amount) external;

    function depositFrom(address sender, uint256 amount) external;

    function depositETHFrom(address sender) external payable;

    function withdraw(uint256 _shares) external;

    function withdrawFrom(address sender, uint256 _shares) external;

    function withdrawETH(uint256 _shares) external;

    function withdrawETHFrom(address sender, uint256 _shares) external;
}
