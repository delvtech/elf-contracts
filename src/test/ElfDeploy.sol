pragma solidity ^0.6.7;

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "../test/AYVault.sol";
import "../test/ALender.sol";
import "../test/ASPV.sol";

import "../test/AToken.sol";
import "../test/APriceOracle.sol";

import "../assets/YdaiAsset.sol";
import "../assets/YtusdAsset.sol";
import "../assets/YusdcAsset.sol";
import "../assets/YusdtAsset.sol";
import "../pools/low/Elf.sol";

contract ElfDeploy {
    WETH public weth;

    Elf public elf;
    ElfAllocator public allocator;

    ALender public lender;

    APriceOracle public priceOracle1;
    APriceOracle public priceOracle2;
    APriceOracle public priceOracle3;
    APriceOracle public priceOracle4;

    AToken public dai;
    AToken public tusd;
    AToken public usdc;
    AToken public usdt;

    ASPV public spv1;
    ASPV public spv2;
    ASPV public spv3;
    ASPV public spv4;

    AYVault public ydai;
    AYVault public ytusd;
    AYVault public yusdc;
    AYVault public yusdt;

    YdaiAsset public ydaiAsset;
    YtusdAsset public ytusdAsset;
    YusdcAsset public yusdcAsset;
    YusdtAsset public yusdtAsset;

    // for testing a basic 4x25% asset percent split
    address[] fromTokens = new address[](4);
    address[] toTokens = new address[](4);
    address[] vehicles = new address[](4);
    uint256[] percents = new uint256[](4);
    address[] assets = new address[](4);

    function init() public {
        weth = new WETH();
        // core element contracts
        elf = new Elf(address(weth));
        allocator = new ElfAllocator(address(elf), address(weth));
        // test implementations
        priceOracle1 = new APriceOracle();
        priceOracle2 = new APriceOracle();
        priceOracle3 = new APriceOracle();
        priceOracle4 = new APriceOracle();
    }

    function config() public {
        // the core contracts need to know the address of each downstream contract:
        // elf -> allocator
        // allocator -> converter, price oracle
        // converter -> lender

        elf.setAllocator(payable(allocator));
        allocator.setPriceOracle(address(priceOracle1));

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

        spv1 = new ASPV(address(weth), address(dai), address(allocator));
        spv2 = new ASPV(address(weth), address(tusd), address(allocator));
        spv3 = new ASPV(address(weth), address(usdc), address(allocator));
        spv4 = new ASPV(address(weth), address(usdt), address(allocator));

        // mint some stablecoins to spvs
        dai.mint(address(spv1), 10000000 ether);
        tusd.mint(address(spv2), 10000000 ether);
        usdc.mint(address(spv3), 10000000 ether);
        usdt.mint(address(spv4), 10000000 ether);

        // provide the test lender with a price oracle
        spv1.setPriceOracle(address(priceOracle1));
        spv2.setPriceOracle(address(priceOracle2));
        spv3.setPriceOracle(address(priceOracle3));
        spv4.setPriceOracle(address(priceOracle4));

        // each asset represents a wrapper around an associated vault
        ydaiAsset = new YdaiAsset(
            payable(allocator),
            address(ydai),
            address(dai)
        );
        ytusdAsset = new YtusdAsset(
            payable(allocator),
            address(ytusd),
            address(tusd)
        );
        yusdcAsset = new YusdcAsset(
            payable(allocator),
            address(yusdc),
            address(usdc)
        );
        yusdtAsset = new YusdtAsset(
            payable(allocator),
            address(usdt),
            address(yusdt)
        );

        // this test requires that we override the hardcoded
        // vault and token addresses with test implementations
        ydaiAsset.setVault(address(ydai));
        ydaiAsset.setToken(address(dai));
        ytusdAsset.setVault(address(ytusd));
        ytusdAsset.setToken(address(tusd));
        yusdcAsset.setVault(address(yusdc));
        yusdcAsset.setToken(address(usdc));
        yusdtAsset.setVault(address(yusdt));
        yusdtAsset.setToken(address(usdt));

        // for testing a basic 4x25% asset percent split
        fromTokens = new address[](4);
        toTokens = new address[](4);
        percents = new uint256[](4);
        assets = new address[](4);
        uint256 _numAllocations = uint256(4);

        // the following block of code initializes the allocations for this test
        fromTokens[0] = address(weth);
        fromTokens[1] = address(weth);
        fromTokens[2] = address(weth);
        fromTokens[3] = address(weth);
        toTokens[0] = address(dai);
        toTokens[1] = address(tusd);
        toTokens[2] = address(usdc);
        toTokens[3] = address(usdt);
        percents[0] = uint256(25);
        percents[1] = uint256(25);
        percents[2] = uint256(25);
        percents[3] = uint256(25);
        assets[0] = address(ydaiAsset);
        assets[1] = address(ytusdAsset);
        assets[2] = address(yusdcAsset);
        assets[3] = address(yusdtAsset);
        vehicles[0] = address(spv1);
        vehicles[1] = address(spv2);
        vehicles[2] = address(spv3);
        vehicles[3] = address(spv4);

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
