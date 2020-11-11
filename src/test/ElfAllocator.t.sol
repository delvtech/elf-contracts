pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./ASPV.sol";
import "./AToken.sol";
import "./ElfDeploy.sol";

import "../assets/YdaiAsset.sol";
import "../assets/YtusdAsset.sol";
import "../assets/YusdcAsset.sol";
import "../assets/YusdtAsset.sol";
import "../pools/low/Elf.sol";

contract ElfAllocatorTest is DSTest {
    WETH weth;

    ElfDeploy elfDeploy;
    Elf elf;
    ElfAllocator allocator;

    AToken dai;
    AToken tusd;
    AToken usdc;

    ASPV spv1;
    ASPV spv2;
    ASPV spv3;

    YdaiAsset ydaiAsset;
    YtusdAsset ytusdAsset;
    YusdcAsset yusdcAsset;

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
        spv1 = elfDeploy.spv1();
        spv2 = elfDeploy.spv2();
        spv3 = elfDeploy.spv3();

        // element asset proxies
        ydaiAsset = elfDeploy.ydaiAsset();
        ytusdAsset = elfDeploy.ytusdAsset();
        yusdcAsset = elfDeploy.yusdcAsset();
    }

    // Verify that allocations that don't sum to 100% fail when calling setAllocations
    function testFail_AllocationPercent() public {
        elfDeploy.changeGovernance(address(this));

        // for testing asset percent split
        address[] memory fromTokens = new address[](3);
        address[] memory toTokens = new address[](3);
        uint256[] memory percents = new uint256[](3);
        address[] memory assets = new address[](3);
        address[] memory vehicles = new address[](3);
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
        vehicles[0] = address(spv1);
        vehicles[1] = address(spv2);
        vehicles[2] = address(spv3);

        allocator.setAllocations(
            fromTokens,
            toTokens,
            vehicles,
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
        address[] memory vehicles = new address[](3);
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
        vehicles[0] = address(spv1);
        vehicles[1] = address(spv2);
        vehicles[2] = address(spv3);

        allocator.setAllocations(
            fromTokens,
            toTokens,
            vehicles,
            percents,
            assets,
            _numAllocations
        );
    }
}
