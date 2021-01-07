pragma solidity >=0.5.8 <0.8.0;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/IWETH.sol";

import "../libraries/ERC20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AToken.sol";
import "./ElfDeploy.sol";

import "../assets/YVaultAssetProxy.sol";
import "../Elf.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract YVaultAssetProxyTest is DSTest {
    Hevm hevm;
    WETH weth;

    ElfDeploy elfDeploy;
    Elf elf;

    AToken usdc;

    YVaultAssetProxy yusdcAsset;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        elfDeploy = new ElfDeploy();
        elfDeploy.init();

        elf = elfDeploy.elf();

        elfDeploy.config();

        // stablecoins
        usdc = elfDeploy.usdc();
        usdc.mint(address(this), 10e6);

        // element asset proxies
        yusdcAsset = elfDeploy.yusdcAsset();
    }

    function test_deposit() public {
        // Normally this will be the elf address but we update temporarily to run the test
        hevm.store(
            address(yusdcAsset),
            bytes32(uint256(3)),
            bytes32(uint256(address(this)))
        );
        usdc.transfer(address(yusdcAsset), 1e6);
        yusdcAsset.deposit();
        assertEq(yusdcAsset.vault().balanceOf(address(this)), 1e6);
    }

    function test_withdraw() public {
        // Normally this will be the elf address but we update temporarily to run the test
        hevm.store(
            address(yusdcAsset),
            bytes32(uint256(3)),
            bytes32(uint256(address(this)))
        );
        usdc.transfer(address(yusdcAsset), 1e6);
        yusdcAsset.deposit();
        yusdcAsset.vault().transfer(
            address(yusdcAsset),
            yusdcAsset.vault().balanceOf(address(this))
        );
        yusdcAsset.withdraw();
        assertEq(usdc.balanceOf(address(this)), 10e6);
    }
}
