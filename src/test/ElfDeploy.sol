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
    WETH weth;

    Elf elf;
    ElfStrategy strategy;

    AToken dai;
    AToken tusd;
    AToken usdc;
    AToken usdt;

    AYVault ydai;
    AYVault ytusd;
    AYVault yusdc;
    AYVault yusdt;

    YdaiAsset ydaiAsset;
    YtusdAsset ytusdAsset;
    YusdcAsset yusdcAsset;
    YusdtAsset yusdtAsset;

    ElementConverter converter;
    ALender lender;
    APriceOracle priceOracle;

    // for testing a basic 4x25% asset percent split
    address[] fromTokens = new address[](4);
    address[] toTokens = new address[](4);
    uint256[] percents = new uint256[](4);
    address[] assets = new address[](4);
    uint256[] conversionType = new uint256[](4);

    function setUp(
        address _weth,
        address _elf,
        address _strategy,
        address _converter,
        address _lender,
        address _priceOracle
    ) public {
        weth = WETH(payable(_weth));
        elf = Elf(payable(_elf));
        strategy = ElfStrategy(payable(_strategy));
        converter = ElementConverter(_converter);
        lender = ALender(payable(_lender));
        priceOracle = APriceOracle(_priceOracle);

        // the core contracts need to know the address of each downstream contract:
        // elf -> strategy
        // strategy -> converter, price oracle
        // converter -> lender
        elf.setStrategy(payable(_strategy));
        strategy.setConverter(_converter);
        strategy.setPriceOracle(_priceOracle);
        converter.setLender(payable(_lender));

        // provide the test lender with a price oracle
        lender.setPriceOracle(_priceOracle);

        // 4 test token implementations
        dai = new AToken(payable(_lender));
        tusd = new AToken(payable(_lender));
        usdc = new AToken(payable(_lender));
        usdt = new AToken(payable(_lender));

        // 4 test vault implementations associated
        // with the 4 test token implementations
        ydai = new AYVault(address(dai));
        ytusd = new AYVault(address(tusd));
        yusdc = new AYVault(address(usdc));
        yusdt = new AYVault(address(usdt));

        // each asset represents a wrapper around an associated vault
        ydaiAsset = new YdaiAsset(payable(_strategy));
        ytusdAsset = new YtusdAsset(payable(_strategy));
        yusdcAsset = new YusdcAsset(payable(_strategy));
        yusdtAsset = new YusdtAsset(payable(_strategy));

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

        // the following block of code initializes the allocations for this test
        uint256 numAllocations = uint256(4);
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
            numAllocations
        );
    }
}
