// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AToken.sol";
import "./ElfDeploy.sol";
import "./WETH.sol";

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

contract ElfAllocatorTest is DSTest {
    Hevm public hevm;
    WETH public weth;

    ElfDeploy public elfDeploy;
    Elf public elf;
    ElfAllocator public allocator;

    AToken public dai;
    AToken public tusd;
    AToken public usdc;

    ALender public lender1;
    ALender public lender2;
    ALender public lender3;

    YdaiAssetProxy public ydaiAsset;
    YtusdAssetProxy public ytusdAsset;
    YusdcAssetProxy public yusdcAsset;

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
        tusd = elfDeploy.tusd();
        usdc = elfDeploy.usdc();

        // lending contracts
        lender1 = elfDeploy.lender1();
        lender2 = elfDeploy.lender2();
        lender3 = elfDeploy.lender3();

        // element asset proxies
        ydaiAsset = elfDeploy.ydaiAsset();
        ytusdAsset = elfDeploy.ytusdAsset();
        yusdcAsset = elfDeploy.yusdcAsset();

        address(this).transfer(1000 ether);
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(this), uint256(3))), // Mint user 1 1000 WETH
            bytes32(uint256(1000 ether))
        );
    }

    // verify that this can only be changed by governance contract
    function testFail_setGovernance() public {
        allocator.setGovernance(address(this));
    }

    // verify that this can only be changed by governance contract
    function testFail_setPool() public {
        allocator.setPool(address(elf));
    }

    // Verify that allocations that don't sum to 100% fail when calling setAllocations
    function testFail_setAllocationPercent() public {
        elfDeploy.changeGovernance(address(this));

        // for testing asset percent split
        address[] memory fromTokens = new address[](3);
        address[] memory toTokens = new address[](3);
        uint256[] memory percents = new uint256[](3);
        address[] memory assets = new address[](3);
        address[] memory lenders = new address[](3);
        uint256 _numAllocations = uint256(3);

        // the following block of code initializes the allocations for this test
        fromTokens[0] = address(weth);
        fromTokens[1] = address(weth);
        fromTokens[2] = address(weth);
        toTokens[0] = address(dai);
        toTokens[1] = address(tusd);
        toTokens[2] = address(usdc);
        percents[0] = uint256(33);
        percents[1] = uint256(33);
        percents[2] = uint256(33);
        assets[0] = address(ydaiAsset);
        assets[1] = address(ytusdAsset);
        assets[2] = address(yusdcAsset);
        lenders[0] = address(lender1);
        lenders[1] = address(lender2);
        lenders[2] = address(lender3);

        allocator.setAllocations(
            fromTokens,
            toTokens,
            lenders,
            percents,
            assets,
            _numAllocations
        );
    }

    // Verify that allocations that sum to 100% DON'T fail when calling setAllocations
    function test_setAllocationPercent() public {
        elfDeploy.changeGovernance(address(this));

        // for testing asset percent split
        address[] memory fromTokens = new address[](3);
        address[] memory toTokens = new address[](3);
        uint256[] memory percents = new uint256[](3);
        address[] memory assets = new address[](3);
        address[] memory lenders = new address[](3);
        uint256 _numAllocations = uint256(3);

        // the following block of code initializes the allocations for this test
        fromTokens[0] = address(weth);
        fromTokens[1] = address(weth);
        fromTokens[2] = address(weth);
        toTokens[0] = address(dai);
        toTokens[1] = address(tusd);
        toTokens[2] = address(usdc);
        percents[0] = uint256(33);
        percents[1] = uint256(33);
        percents[2] = uint256(34);
        assets[0] = address(ydaiAsset);
        assets[1] = address(ytusdAsset);
        assets[2] = address(yusdcAsset);
        lenders[0] = address(lender1);
        lenders[1] = address(lender2);
        lenders[2] = address(lender3);

        allocator.setAllocations(
            fromTokens,
            toTokens,
            lenders,
            percents,
            assets,
            _numAllocations
        );

        assertEq(allocator.getNumAllocations(), 3);
    }

    // Verify the we get back the allocations we set
    function test_getAllocations() public {
        elfDeploy.changeGovernance(address(this));

        // for testing asset percent split
        address[] memory fromTokens = new address[](3);
        address[] memory toTokens = new address[](3);
        uint256[] memory percents = new uint256[](3);
        address[] memory assets = new address[](3);
        address[] memory lenders = new address[](3);
        uint256 _numAllocations = uint256(3);

        // the following block of code initializes the allocations for this test
        fromTokens[0] = address(weth);
        fromTokens[1] = address(weth);
        fromTokens[2] = address(weth);
        toTokens[0] = address(dai);
        toTokens[1] = address(tusd);
        toTokens[2] = address(usdc);
        percents[0] = uint256(33);
        percents[1] = uint256(33);
        percents[2] = uint256(34);
        assets[0] = address(ydaiAsset);
        assets[1] = address(ytusdAsset);
        assets[2] = address(yusdcAsset);
        lenders[0] = address(lender1);
        lenders[1] = address(lender2);
        lenders[2] = address(lender3);

        allocator.setAllocations(
            fromTokens,
            toTokens,
            lenders,
            percents,
            assets,
            _numAllocations
        );

        (
            address[] memory fromTokensResult,
            address[] memory toTokensResult,
            address[] memory lendersResult,
            uint256[] memory percentsResult,
            address[] memory assetsResult,
            uint256 numAllocationsResult
        ) = allocator.getAllocations();

        for (uint256 i = 0; i < fromTokens.length; i++) {
            assertEq(fromTokens[i], fromTokensResult[i]);
        }
        for (uint256 i = 0; i < fromTokens.length; i++) {
            assertEq(toTokens[i], toTokensResult[i]);
        }
        for (uint256 i = 0; i < fromTokens.length; i++) {
            assertEq(lenders[i], lendersResult[i]);
        }
        for (uint256 i = 0; i < fromTokens.length; i++) {
            assertEq(percents[i], percentsResult[i]);
        }
        for (uint256 i = 0; i < fromTokens.length; i++) {
            assertEq(assets[i], assetsResult[i]);
        }
        assertEq(_numAllocations, numAllocationsResult);
    }

    function test_Allocate() public {
        elfDeploy.changeGovernance(address(this));
        allocator.setPool(address(this));

        // setup allocations
        address[] memory fromTokens = new address[](3);
        address[] memory toTokens = new address[](3);
        uint256[] memory percents = new uint256[](3);
        address[] memory assets = new address[](3);
        address[] memory lenders = new address[](3);
        uint256 _numAllocations = uint256(3);
        fromTokens[0] = address(weth);
        fromTokens[1] = address(weth);
        fromTokens[2] = address(weth);
        toTokens[0] = address(dai);
        toTokens[1] = address(tusd);
        toTokens[2] = address(usdc);
        percents[0] = uint256(33);
        percents[1] = uint256(33);
        percents[2] = uint256(34);
        assets[0] = address(ydaiAsset);
        assets[1] = address(ytusdAsset);
        assets[2] = address(yusdcAsset);
        lenders[0] = address(lender1);
        lenders[1] = address(lender2);
        lenders[2] = address(lender3);
        allocator.setAllocations(
            fromTokens,
            toTokens,
            lenders,
            percents,
            assets,
            _numAllocations
        );

        uint256 amount = weth.balanceOf(address(this));
        weth.transfer(address(allocator), amount);
        allocator.allocate(amount);
        assertEq(
            weth.balanceOf(address(lender1)) +
                weth.balanceOf(address(lender2)) +
                weth.balanceOf(address(lender3)),
            amount
        );
    }

    function test_Deallocate() public {
        elfDeploy.changeGovernance(address(this));
        allocator.setPool(address(this));

        // setup allocations
        address[] memory fromTokens = new address[](3);
        address[] memory toTokens = new address[](3);
        uint256[] memory percents = new uint256[](3);
        address[] memory assets = new address[](3);
        address[] memory lenders = new address[](3);
        uint256 _numAllocations = uint256(3);
        fromTokens[0] = address(weth);
        fromTokens[1] = address(weth);
        fromTokens[2] = address(weth);
        toTokens[0] = address(dai);
        toTokens[1] = address(tusd);
        toTokens[2] = address(usdc);
        percents[0] = uint256(33);
        percents[1] = uint256(33);
        percents[2] = uint256(34);
        assets[0] = address(ydaiAsset);
        assets[1] = address(ytusdAsset);
        assets[2] = address(yusdcAsset);
        lenders[0] = address(lender1);
        lenders[1] = address(lender2);
        lenders[2] = address(lender3);
        allocator.setAllocations(
            fromTokens,
            toTokens,
            lenders,
            percents,
            assets,
            _numAllocations
        );

        uint256 amount = weth.balanceOf(address(this));
        weth.transfer(address(allocator), amount);
        allocator.allocate(amount);

        allocator.deallocate(amount);

        assertEq(weth.balanceOf(address(allocator)), amount);
    }

    receive() external payable {}
}
