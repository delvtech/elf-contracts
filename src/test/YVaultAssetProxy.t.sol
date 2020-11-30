pragma solidity >=0.5.8 <0.8.0;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/IWETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AToken.sol";
import "./ElfDeploy.sol";

import "../assets/YdaiAssetProxy.sol";
import "../assets/YtusdAssetProxy.sol";
import "../assets/YusdcAssetProxy.sol";
import "../assets/YusdtAssetProxy.sol";
import "../pools/low/Elf.sol";

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
    ElfAllocator allocator;

    AToken dai;

    ALender lender1;

    YdaiAssetProxy ydaiAsset;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        elfDeploy = new ElfDeploy();
        elfDeploy.init();

        weth = elfDeploy.weth();
        elf = elfDeploy.elf();
        allocator = elfDeploy.allocator();

        elfDeploy.config();

        // stablecoins
        dai = elfDeploy.dai();

        // lending contracts
        lender1 = elfDeploy.lender1();

        // element asset proxies
        ydaiAsset = elfDeploy.ydaiAsset();

        payable(this).transfer(1000 ether);
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(this), uint256(3))), // Mint user 1 1000 WETH
            bytes32(uint256(1000 ether))
        );
    }

    // verify that this can only be changed by governance contract
    function testFail_setGovernance() public {
        ydaiAsset.setGovernance(address(this));
    }

    // verify that this can only be changed by governance contract
    function testFail_setAllocator() public {
        ydaiAsset.setAllocator(address(allocator));
    }

    // verify that this can only be changed by governance contract
    function testFail_setVault() public {
        ydaiAsset.setVault(address(elfDeploy.ydai()));
    }

    // verify that this can only be changed by governance contract
    function testFail_setToken() public {
        ydaiAsset.setToken(address(elfDeploy.dai()));
    }

    function testFail_notAllowedToCallDeposit() public {
        // set vault so the test should pass ONLY if the correct address calls deposit
        elfDeploy.changeGovernance(address(this));
        ydaiAsset.setVault(address(elfDeploy.ydai()));
        //ensure the asset proxy has enough of the base asset to transfer to vault
        dai.mint(address(ydaiAsset), 10000000 ether);
        //this should FAIL bc the calling address is not the allocator
        ydaiAsset.deposit(100);
    }

    function test_deposit() public {
        elfDeploy.changeGovernance(address(this));
        ydaiAsset.setVault(address(elfDeploy.ydai()));
        ydaiAsset.setAllocator(address(this));
        //ensure the asset proxy has enough of the base asset to transfer to vault
        dai.mint(address(ydaiAsset), 10000000 ether);
        //this should PASS bc the calling address is the allocator
        ydaiAsset.deposit(100);
    }

    function testFail_notAllowedToCallWithdraw() public {
        // configure test to not throw exception for deposit
        elfDeploy.changeGovernance(address(this));
        ydaiAsset.setVault(address(elfDeploy.ydai()));
        ydaiAsset.setAllocator(address(this));
        //ensure the asset proxy has enough of the base asset to transfer to vault
        dai.mint(address(ydaiAsset), 10000000 ether);
        //this should PASS bc the calling address is not the allocator
        ydaiAsset.deposit(100);
        // this should cause withdraw() to fail since the calling contract is not the allocator
        ydaiAsset.setAllocator(address(allocator));
        // transfer vault shares to asset proxy
        elfDeploy.ydai().transfer(address(ydaiAsset), 100);
        // withdraw base asset
        ydaiAsset.withdraw(100, address(this));
    }

    function test_withdraw() public {
        // configure test to not throw exception for deposit or withdraw
        elfDeploy.changeGovernance(address(this));
        ydaiAsset.setVault(address(elfDeploy.ydai()));
        ydaiAsset.setAllocator(address(this));
        //ensure the asset proxy has enough of the base asset to transfer to vault
        dai.mint(address(ydaiAsset), 10000000 ether);
        //this should PASS bc the calling address is not the allocator
        ydaiAsset.deposit(100);

        // transfer vault shares to asset proxy
        elfDeploy.ydai().transfer(address(ydaiAsset), 100);
        // withdraw base asset
        ydaiAsset.withdraw(100, address(this));
    }

    receive() external payable {}
}
