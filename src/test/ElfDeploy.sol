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

    ElfProxy public proxy;
    ElfFactory public factory;
    Elf public elf;

    AToken public dai;
    AToken public tusd;
    AToken public usdc;
    AToken public usdt;

    AYVault public ydai;
    AYVault public ytusd;
    AYVault public yusdc;
    AYVault public yusdt;

    YVaultAssetProxy public ydaiAsset;
    YVaultAssetProxy public ytusdAsset;
    YVaultAssetProxy public yusdcAsset;
    YVaultAssetProxy public yusdtAsset;

    // for testing a basic 4x25% asset percent split
    address[] public fromTokens = new address[](4);
    address[] public toTokens = new address[](4);
    address[] public assets = new address[](4);

    function init() public {
        weth = new WETH();
        proxy = new ElfProxy();
        factory = new ElfFactory();
        // elf = factory.newPool(address(weth));
    }

    function config() public {
        dai = new AToken(address(this));
        tusd = new AToken(address(this));
        usdc = new AToken(address(this));
        usdt = new AToken(address(this));

        // 4 test token implementations
        // 4 test vault implementations associated
        // with the 4 test token implementations
        ydai = new AYVault(address(dai));
        ytusd = new AYVault(address(tusd));
        yusdc = new AYVault(address(usdc));
        yusdt = new AYVault(address(usdt));

        // each asset represents a wrapper around an associated vault
        ydaiAsset = new YVaultAssetProxy(
            address(elf),
            address(ydai),
            address(dai)
        );
        ytusdAsset = new YVaultAssetProxy(
            address(elf),
            address(ytusd),
            address(tusd)
        );
        yusdcAsset = new YVaultAssetProxy(
            address(elf),
            address(yusdc),
            address(usdc)
        );
        yusdtAsset = new YVaultAssetProxy(
            address(elf),
            address(yusdt),
            address(usdt)
        );
    }

    function changeGovernance(address _governance) public {
        ydaiAsset.setGovernance(_governance);
    }
}
