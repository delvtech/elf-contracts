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
import "../ElfFactory.sol";

contract ElfDeploy {
    WETH public weth;

    ElfFactory public factory;
    Elf public elf;

    AToken public usdc;
    AYVault public yusdc;
    YVaultAssetProxy public yusdcAsset;

    function init() public {
        weth = new WETH();
        Elf masterElf = new Elf();
        YVaultAssetProxy masterProxy = new YVaultAssetProxy();
        factory = new ElfFactory(address(masterProxy), address(masterElf));
    }

    function config() public {
        usdc = new AToken(address(this));
        yusdc = new AYVault(address(usdc));

        elf = factory.newPool(address(usdc), address(yusdc));
        yusdcAsset = YVaultAssetProxy(address(elf.proxy()));
    }
}
