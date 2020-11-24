// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

interface IElf {
    function balance() external view returns (uint256);

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
