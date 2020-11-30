// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AYVault.sol";
import "./ALender.sol";
import "./WETH.sol";
import "./AToken.sol";
import "./APriceOracle.sol";

import "../assets/YVaultAssetProxy.sol";
import "../Elf.sol";
import "../proxy/ElfProxy.sol";
import "../ElfFactory.sol";

contract ElfDeploy {
    WETH public weth;

    ElfProxy public proxy;
    ElfFactory public factory;
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

    ALender public lender1;
    ALender public lender2;
    ALender public lender3;
    ALender public lender4;

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
    address[] public lenders = new address[](4);
    uint256[] public percents = new uint256[](4);
    address[] public assets = new address[](4);

    function init() public {
        weth = new WETH();
        proxy = new ElfProxy();
        factory = new ElfFactory();
        elf = factory.newPool(address(weth));
        allocator = ElfAllocator(elf.getAllocator());
    }

    function config() public {
        // test implementations
        priceOracle1 = new APriceOracle();
        priceOracle2 = new APriceOracle();
        priceOracle3 = new APriceOracle();
        priceOracle4 = new APriceOracle();

        // the core contracts need to know the address of each downstream contract:
        // elf -> allocator
        // allocator -> converter, price oracle
        // converter -> lender

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

        lender1 = new ALender(address(weth), address(dai), address(allocator));
        lender2 = new ALender(address(weth), address(tusd), address(allocator));
        lender3 = new ALender(address(weth), address(usdc), address(allocator));
        lender4 = new ALender(address(weth), address(usdt), address(allocator));

        // mint some stablecoins
        dai.mint(address(lender1), 10000000 ether);
        tusd.mint(address(lender2), 10000000 ether);
        usdc.mint(address(lender3), 10000000 ether);
        usdt.mint(address(lender4), 10000000 ether);

        // provide the test lender with a price oracle
        lender1.setPriceOracle(address(priceOracle1));
        lender2.setPriceOracle(address(priceOracle2));
        lender3.setPriceOracle(address(priceOracle3));
        lender4.setPriceOracle(address(priceOracle4));

        // each asset represents a wrapper around an associated vault
        ydaiAsset = new YVaultAssetProxy(
            address(allocator),
            address(ydai),
            address(dai)
        );
        ytusdAsset = new YVaultAssetProxy(
            address(allocator),
            address(ytusd),
            address(tusd)
        );
        yusdcAsset = new YVaultAssetProxy(
            address(allocator),
            address(yusdc),
            address(usdc)
        );
        yusdtAsset = new YVaultAssetProxy(
            address(allocator),
            address(yusdt),
            address(usdt)
        );

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
        lenders[0] = address(lender1);
        lenders[1] = address(lender2);
        lenders[2] = address(lender3);
        lenders[3] = address(lender4);

        allocator.setAllocations(
            fromTokens,
            toTokens,
            lenders,
            percents,
            assets,
            _numAllocations
        );
    }

    function changeGovernance(address _governance) public {
        allocator.setGovernance(_governance);
        ydaiAsset.setGovernance(_governance);
    }
}
