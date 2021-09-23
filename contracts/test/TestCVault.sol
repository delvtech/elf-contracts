// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../CompoundAssetProxy.sol";

import "../libraries/ERC20PermitWithSupply.sol";

import "../libraries/ERC20Permit.sol";
import "./TestERC20.sol";

contract TestCVault is CompoundAssetProxy {}
