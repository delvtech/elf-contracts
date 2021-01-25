// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";

import "../libraries/ERC20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AYVault.sol";
import "./AToken.sol";
import "./WETH.sol";

import "../assets/YVaultAssetProxy.sol";
import "../Elf.sol";
import "../ElfFactory.sol";

/// @author Element Finance
/// @title Elf Deploy
contract ElfDeploy {
    WETH public weth;

    ElfFactory public factory;
    Elf public elf;

    AToken public usdc;
    AYVault public yusdc;
    YVaultAssetProxy public yusdcAsset;

    /// @notice deploy weth and factory contracts
    function init() public {
        weth = new WETH();
        factory = new ElfFactory();
    }

    /// @notice deploy assets and elf pool
    function config() public {
        usdc = new AToken(address(this));
        yusdc = new AYVault(address(usdc));
        // each asset represents a wrapper around an associated vault
        yusdcAsset = new YVaultAssetProxy(address(yusdc), address(usdc));

        elf = factory.newPool(address(usdc), address(yusdcAsset));
    }

    /// @notice update governance from this contract to testing contract
    /// @param _governance new governance address
    function changeGovernance(address _governance) public {
        yusdcAsset.setGovernance(_governance);
        elf.setGovernance(_governance);
    }
}
