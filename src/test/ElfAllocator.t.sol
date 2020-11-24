// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AToken.sol";
import "./ElfDeploy.sol";

import "../assets/YdaiAsset.sol";
import "../assets/YtusdAsset.sol";
import "../assets/YusdcAsset.sol";
import "../assets/YusdtAsset.sol";
import "../pools/low/Elf.sol";

contract ElfAllocatorTest is DSTest {
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

    YdaiAsset public ydaiAsset;
    YtusdAsset public ytusdAsset;
    YusdcAsset public yusdcAsset;

    function setUp() public {
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
    }

    // verify that this can only be changed by governance contract
    function testFail_setGovernance() public {
        allocator.setGovernance(address(this));
    }

    // verify that this can only be changed by governance contract
    function testFail_setConverter() public {
        allocator.setConverter(address(this));
    }

    // verify that this can only be changed by governance contract
    function testFail_setPriceOracle() public {
        allocator.setPriceOracle(address(this));
    }

    // Verify that allocations that don't sum to 100% fail when calling setAllocations
    function testFail_AllocationPercent() public {
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
    function test_AllocationPercent() public {
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

        assertEq(allocator.numAllocations(), 3);
    }
}
