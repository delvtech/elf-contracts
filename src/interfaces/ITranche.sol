// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.16;

import "./IERC20Permit.sol";

interface ITranche is IERC20Permit {

    function deposit(uint256 _shares) external returns(uint256);

    function withdrawFyt(uint256 _amount) external returns(uint256);

    function withdrawYc(uint256 _amount) external returns(uint256);

    function getYC() external view returns(address);
}