pragma solidity ^0.6.7;

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "../test/AYVault.sol";
import "../test/ALender.sol";

import "../test/AToken.sol";
import "../test/APriceOracle.sol";
import "../converter/ElementConverter.sol";

import "../assets/YdaiAsset.sol";
import "../assets/YtusdAsset.sol";
import "../assets/YusdcAsset.sol";
import "../assets/YusdtAsset.sol";
import "../pools/low/Elf.sol";

contract ElfDeploy {
    WETH public weth;

    Elf public elf;
    ElfStrategy public strategy;
    ElementConverter public converter;

    ALender public lender;
    APriceOracle public priceOracle;

    AToken public dai;
    AToken public tusd;
    AToken public usdc;
    AToken public usdt;

    AYVault public ydai;
    AYVault public ytusd;
    AYVault public yusdc;
    AYVault public yusdt;

    YdaiAsset public ydaiAsset;
    YtusdAsset public ytusdAsset;
    YusdcAsset public yusdcAsset;
    YusdtAsset public yusdtAsset;

    // for testing a basic 4x25% asset percent split
    address[] public fromTokens = new address[](4);
    address[] public toTokens = new address[](4);
    uint256[] public percents = new uint256[](4);
    address[] public assets = new address[](4);
    uint256[] public conversionType = new uint256[](4);

    function init() public {
        weth = new WETH();
        // core element contracts
        elf = new Elf(address(weth));
        strategy = new ElfStrategy(address(elf), address(weth));
        converter = new ElementConverter(address(weth));
        // test implementations
        lender = new ALender(address(converter), address(weth));
        priceOracle = new APriceOracle();
    }

    function config() public {
        // the core contracts need to know the address of each downstream contract:
        // elf -> strategy
        // strategy -> converter, price oracle
        // converter -> lender
        elf.setStrategy(payable(strategy));
        strategy.setConverter(address(converter));
        strategy.setPriceOracle(address(priceOracle));
        converter.setLender(payable(lender));

        // provide the test lender with a price oracle
        lender.setPriceOracle(address(priceOracle));

        // 4 test token implementations
        dai = new AToken(payable(lender));
        tusd = new AToken(payable(lender));
        usdc = new AToken(payable(lender));
        usdt = new AToken(payable(lender));

        // 4 test vault implementations associated
        // with the 4 test token implementations
        ydai = new AYVault(address(dai));
        ytusd = new AYVault(address(tusd));
        yusdc = new AYVault(address(usdc));
        yusdt = new AYVault(address(usdt));

        // each asset represents a wrapper around an associated vault
        ydaiAsset = new YdaiAsset(payable(strategy));
        ytusdAsset = new YtusdAsset(payable(strategy));
        yusdcAsset = new YusdcAsset(payable(strategy));
        yusdtAsset = new YusdtAsset(payable(strategy));

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
        conversionType = new uint256[](4);
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
        conversionType[0] = uint256(0);
        conversionType[1] = uint256(0);
        conversionType[2] = uint256(0);
        conversionType[3] = uint256(0);
        strategy.setAllocations(
            fromTokens,
            toTokens,
            percents,
            assets,
            conversionType,
            _numAllocations
        );
    }
}
