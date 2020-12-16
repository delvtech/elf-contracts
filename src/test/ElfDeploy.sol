// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

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
import "../ElfProxy.sol";
import "../ElfFactory.sol";

contract ElfDeploy {
    WETH public weth;

    ElfFactory public factory;
    Elf public elf;

    AToken public usdc;
    AYVault public yusdc;
    YVaultAssetProxy public yusdcAsset;

    function init() public {
        factory = new ElfFactory();
    }

    function config() public {
        usdc = new AToken(address(this));
        yusdc = new AYVault(address(usdc));
        // each asset represents a wrapper around an associated vault
        yusdcAsset = new YVaultAssetProxy(address(yusdc), address(usdc));

        elf = factory.newPool(address(usdc), address(yusdcAsset));
    }

    function changeGovernance(address _governance) public {
        yusdcAsset.setGovernance(_governance);
        elf.setGovernance(_governance);
    }
}
