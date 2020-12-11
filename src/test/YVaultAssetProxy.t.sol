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

    AToken dai;

    YVaultAssetProxy ydaiAsset;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        elfDeploy = new ElfDeploy();
        elfDeploy.init();

        weth = elfDeploy.weth();
        elf = elfDeploy.elf();

        elfDeploy.config();

        // stablecoins
        dai = elfDeploy.dai();

        // element asset proxies
        ydaiAsset = elfDeploy.ydaiAsset();


    }
}
