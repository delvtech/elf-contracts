pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AYVault.sol";
import "./ALender.sol";
import "./AToken.sol";
import "./APriceOracle.sol";
import "./ElfDeploy.sol";
import "../lenders/aave/AaveLender.sol";

import "../converter/ElementConverter.sol";
import "../assets/YdaiAsset.sol";
import "../assets/YtusdAsset.sol";
import "../assets/YusdcAsset.sol";
import "../assets/YusdtAsset.sol";
import "../pools/low/Elf.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract User {
    // max uint approve for spending
    function approve(address _token, address _guy) public {
        IERC20(_token).approve(_guy, uint256(-1));
    }

    // depositing WETH and minting
    function call_deposit(address payable _obj, uint256 _amount) public {
        Elf(_obj).deposit(_amount);
    }

    // deposit ETH, converting to WETH, and minting
    function call_depositETH(address payable _obj, uint256 _amount)
        public
        payable
    {
        Elf(_obj).depositETH{value: _amount}();
    }

    // withdraw specific shares to WETH
    function call_withdraw(address payable _obj, uint256 _amount) public {
        Elf(_obj).withdraw(_amount);
    }

    // withdraw specific shares to ETH
    function call_withdrawETH(address payable _obj, uint256 _amount) public {
        Elf(_obj).withdrawETH(_amount);
    }

    // to be able to receive funds
    receive() external payable {}
}

contract ElfContractsTest is DSTest {
    Hevm hevm;
    WETH weth;

    Elf elf;
    ElfStrategy strategy;
    ElementConverter converter;

    AaveLender aaveLender;

    ALender lender1;
    APriceOracle priceOracle;

    User user1;
    User user2;
    User user3;

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

    // for testing a basic 4x25% asset percent split
    address[] fromTokens = new address[](4);
    address[] toTokens = new address[](4);
    uint256[] percents = new uint256[](4);
    address[] assets = new address[](4);
    uint256[] conversionType = new uint256[](4);

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant CORE = 0x3dfd23A6c5E8BbcFc9581d2E864a68feb6a076d3;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        ElfDeploy _elfDeploy = new ElfDeploy();
        _elfDeploy.init();
        weth = _elfDeploy.weth();
        elf = _elfDeploy.elf();
        strategy = _elfDeploy.strategy();
        converter = _elfDeploy.converter();
        lender1 = _elfDeploy.lender();
        priceOracle = _elfDeploy.priceOracle();
        _elfDeploy.config();
        dai = _elfDeploy.dai();
        tusd = _elfDeploy.tusd();
        usdc = _elfDeploy.usdc();
        usdt = _elfDeploy.usdt();
        ydai = _elfDeploy.ydai();
        ytusd = _elfDeploy.ytusd();
        yusdc = _elfDeploy.yusdc();
        yusdt = _elfDeploy.yusdt();
        ydaiAsset = _elfDeploy.ydaiAsset();
        ytusdAsset = _elfDeploy.ytusdAsset();
        yusdcAsset = _elfDeploy.yusdcAsset();
        yusdtAsset = _elfDeploy.yusdtAsset();

        // create 3 users and provide funds
        user1 = new User();
        user2 = new User();
        user3 = new User();
        address(user1).transfer(1000 ether);
        address(user2).transfer(1000 ether);
        address(user3).transfer(1000 ether);
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user1), uint256(3))), // Mint user 1 1000 WETH
            bytes32(uint256(1000 ether))
        );
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user2), uint256(3))), // Mint user 2 1000 WETH
            bytes32(uint256(1000 ether))
        );
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user3), uint256(3))), // Mint user 3 1000 WETH
            bytes32(uint256(1000 ether))
        );
        hevm.store(
            address(DAI),
            keccak256(abi.encode(address(this), uint256(2))), // Mint this address 100000 DAI
            bytes32(uint256(100000 ether))
        );
    }

    function test_correctUserBalances() public {
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
    }

    function test_depositingETH() public {
        // deposit eth
        user1.call_depositETH(address(elf), 1 ether);

        // verify that weth made it all the way to the lender
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 1 ether);

        // verify that the dai asset and dai vault contain the expected balances
        uint256 expectedTokenBalance = lender1.getLendingPrice(
            address(weth),
            address(dai)
        ) * 250 finney;
        assertEq(ydaiAsset.balance(), expectedTokenBalance); // NOTE: dai to ydai is 1:1
        assertEq(IERC20(dai).balanceOf(address(ydai)), expectedTokenBalance);

        // verify that the tusd asset and tusd vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(tusd)) *
            250 finney;
        assertEq(ytusdAsset.balance(), expectedTokenBalance); // NOTE: tusd to ytusd is 1:1
        assertEq(IERC20(tusd).balanceOf(address(ytusd)), expectedTokenBalance);

        // verify that the usdc asset and usdc vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(usdc)) *
            250 finney;
        assertEq(yusdcAsset.balance(), expectedTokenBalance); // NOTE: usdc to yusdc is 1:1
        assertEq(IERC20(usdc).balanceOf(address(yusdc)), expectedTokenBalance);

        // verify that the usdt asset and usdt vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(usdt)) *
            250 finney;
        assertEq(yusdtAsset.balance(), expectedTokenBalance); // NOTE: usdt to yusdt is 1:1
        assertEq(IERC20(usdt).balanceOf(address(yusdt)), expectedTokenBalance);

        // verify that the proper amount of elf was minted
        assertEq(elf.totalSupply(), 1 ether);
        // verify that the balance calculation matches the deposited eth
        assertEq(elf.balance(), 1 ether);
    }

    function test_depositingWETH() public {
        // deposit eth
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);

        // verify that weth made it all the way to the lender
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 1 ether);

        // verify that the dai asset and dai vault contain the expected balances
        uint256 expectedTokenBalance = lender1.getLendingPrice(
            address(weth),
            address(dai)
        ) * 250 finney;
        assertEq(ydaiAsset.balance(), expectedTokenBalance);

        // verify that the tusd asset and tusd vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(tusd)) *
            250 finney;
        assertEq(ytusdAsset.balance(), expectedTokenBalance);

        // verify that the usdc asset and usdc vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(usdc)) *
            250 finney;
        assertEq(yusdcAsset.balance(), expectedTokenBalance);

        // verify that the usdt asset and usdt vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(usdt)) *
            250 finney;
        assertEq(yusdtAsset.balance(), expectedTokenBalance);

        // verify that the proper amount of elf was minted
        assertEq(elf.totalSupply(), 1 ether);
        // verify that the balance calculation matches the deposited eth
        assertEq(elf.balance(), 1 ether);
    }

    function test_multipleETHDeposits() public {
        // Deposit 1
        user1.call_depositETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 1 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 1 ether);
        uint256 expectedDaiBalance = lender1.getLendingPrice(
            address(weth),
            address(dai)
        ) * 250 finney;
        assertEq(ydaiAsset.balance(), expectedDaiBalance);
        uint256 expectedTusdBalance = lender1.getLendingPrice(
            address(weth),
            address(tusd)
        ) * 250 finney;
        assertEq(ytusdAsset.balance(), expectedTusdBalance);
        uint256 expectedUsdcBalance = lender1.getLendingPrice(
            address(weth),
            address(usdc)
        ) * 250 finney;
        assertEq(yusdcAsset.balance(), expectedUsdcBalance);
        uint256 expectedUsdtBalance = lender1.getLendingPrice(
            address(weth),
            address(usdt)
        ) * 250 finney;
        assertEq(yusdtAsset.balance(), expectedUsdtBalance);
        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        // Deposit 2
        user2.call_depositETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 2 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 2 ether);
        expectedDaiBalance +=
            lender1.getLendingPrice(address(weth), address(dai)) *
            250 finney;
        assertEq(ydaiAsset.balance(), expectedDaiBalance);
        expectedTusdBalance +=
            lender1.getLendingPrice(address(weth), address(tusd)) *
            250 finney;
        assertEq(ytusdAsset.balance(), expectedTusdBalance);
        expectedUsdcBalance +=
            lender1.getLendingPrice(address(weth), address(usdc)) *
            250 finney;
        assertEq(yusdcAsset.balance(), expectedUsdcBalance);
        expectedUsdtBalance +=
            lender1.getLendingPrice(address(weth), address(usdt)) *
            250 finney;
        assertEq(yusdtAsset.balance(), expectedUsdtBalance);
        assertEq(elf.balance(), 2 ether);
        assertEq(elf.balanceOf(address(user2)), 1 ether);

        // Deposit 3
        user3.call_depositETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 3 ether);
        expectedDaiBalance +=
            lender1.getLendingPrice(address(weth), address(dai)) *
            250 finney;
        assertEq(ydaiAsset.balance(), expectedDaiBalance);
        expectedTusdBalance +=
            lender1.getLendingPrice(address(weth), address(tusd)) *
            250 finney;
        assertEq(ytusdAsset.balance(), expectedTusdBalance);
        expectedUsdcBalance +=
            lender1.getLendingPrice(address(weth), address(usdc)) *
            250 finney;
        assertEq(yusdcAsset.balance(), expectedUsdcBalance);
        expectedUsdtBalance +=
            lender1.getLendingPrice(address(weth), address(usdt)) *
            250 finney;
        assertEq(yusdtAsset.balance(), expectedUsdtBalance);
        assertEq(elf.balance(), 3 ether);
        assertEq(elf.balanceOf(address(user3)), 1 ether);
    }

    function test_multipleWETHDeposits() public {
        // Deposit 1
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 1 ether);
        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        // Deposit 2
        user2.approve(address(weth), address(elf));
        user2.call_deposit(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 2 ether);
        assertEq(elf.balance(), 2 ether);
        assertEq(elf.balanceOf(address(user2)), 1 ether);

        // Deposit 3
        user3.approve(address(weth), address(elf));
        user3.call_deposit(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(elf.balance(), 3 ether);
        assertEq(elf.balanceOf(address(user3)), 1 ether);
    }

    function test_multipleWETHDepositsAndWithdraws() public {
        // verify starting balance
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
        assertEq(dai.balanceOf(address(lender1)), 1000000000000000000000 ether);
        assertEq(
            tusd.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );
        assertEq(
            usdc.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );
        assertEq(
            usdt.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );

        // 3 deposits
        user1.approve(address(weth), address(elf));
        user2.approve(address(weth), address(elf));
        user3.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        user2.call_deposit(address(elf), 1 ether);
        user3.call_deposit(address(elf), 1 ether);
        assertEq(weth.balanceOf(address(user1)), 999 ether);
        assertEq(weth.balanceOf(address(user2)), 999 ether);
        assertEq(weth.balanceOf(address(user3)), 999 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(lender1)), 3 ether);

        assertEq(
            dai.balanceOf(address(lender1)),
            699625 * 1000000000000000 ether
        ); // - 3/4 * 400.5 Dai/ 1 ETH
        assertEq(
            tusd.balanceOf(address(lender1)),
            699625 * 1000000000000000 ether
        ); // - 3/4 * 400.5 tusd/ 1 ETH
        assertEq(
            usdc.balanceOf(address(lender1)),
            699625 * 1000000000000000 ether
        ); // - 3/4 * 400.5 usdc/ 1 ETH
        assertEq(
            usdt.balanceOf(address(lender1)),
            699625 * 1000000000000000 ether
        ); // - 3/4 * 400.5 usdt/ 1 ETH

        // 3 withdraws
        user1.call_withdraw(address(elf), 1 ether);
        user2.call_withdraw(address(elf), 1 ether);
        user3.call_withdraw(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 0 ether);
        assertEq(dai.balanceOf(address(lender1)), 1000000000000000000000 ether);
        assertEq(
            tusd.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );
        assertEq(
            usdc.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );
        assertEq(
            usdt.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );

        // validate ending balance
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
    }

    function test_multipleETHDepositsAndWithdraws() public {
        // verify starting balance
        assertEq(address(user1).balance, 1000 ether);
        assertEq(address(user2).balance, 1000 ether);
        assertEq(address(user3).balance, 1000 ether);
        assertEq(dai.balanceOf(address(lender1)), 1000000000000000000000 ether);
        assertEq(
            tusd.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );
        assertEq(
            usdc.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );
        assertEq(
            usdt.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );

        // 3 deposits
        user1.call_depositETH(address(elf), 1 ether);
        user2.call_depositETH(address(elf), 1 ether);
        user3.call_depositETH(address(elf), 1 ether);
        assertEq(address(user1).balance, 999 ether);
        assertEq(address(user2).balance, 999 ether);
        assertEq(address(user3).balance, 999 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(lender1)), 3 ether);
        assertEq(
            dai.balanceOf(address(lender1)),
            699625 * 1000000000000000 ether
        ); // - 3/4 * 400.5 Dai/ 1 ETH
        assertEq(
            tusd.balanceOf(address(lender1)),
            699625 * 1000000000000000 ether
        ); // - 3/4 * 400.5 tusd/ 1 ETH
        assertEq(
            usdc.balanceOf(address(lender1)),
            699625 * 1000000000000000 ether
        ); // - 3/4 * 400.5 usdc/ 1 ETH
        assertEq(
            usdt.balanceOf(address(lender1)),
            699625 * 1000000000000000 ether
        ); // - 3/4 * 400.5 usdt/ 1 ETH

        // 3 withdraws
        user1.call_withdrawETH(address(elf), 1 ether);
        user2.call_withdrawETH(address(elf), 1 ether);
        user3.call_withdrawETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 0 ether);
        assertEq(dai.balanceOf(address(lender1)), 1000000000000000000000 ether);
        assertEq(
            tusd.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );
        assertEq(
            usdc.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );
        assertEq(
            usdt.balanceOf(address(lender1)),
            1000000000000000000000 ether
        );

        // validate ending balance
        assertEq(address(user1).balance, 1000 ether);
        assertEq(address(user2).balance, 1000 ether);
        assertEq(address(user3).balance, 1000 ether);
    }

    function test_aave_DAI_deposit_integration() public {
        aaveLender = new AaveLender();
        IERC20 dai = IERC20(DAI);

        dai.transfer(address(aaveLender), 25 ether);
        aaveLender.depositCollateral{value: 0 ether}(DAI, 25 ether);
    }

    function test_aave_DAI_deposit_redeem_integration() public {
        aaveLender = new AaveLender();
        IERC20 dai = IERC20(DAI);

        dai.transfer(address(aaveLender), 25 ether);
        aaveLender.depositCollateral{value: 0 ether}(DAI, 25 ether);
        aaveLender.redeem(address(dai), 5 ether);
    }

    function test_aave_ETH_deposit_integration() public {
        aaveLender = new AaveLender();

        aaveLender.depositCollateral{value: 25 ether}(ETH, 25 ether);
    }

    function test_aave_ETH_deposit_DAI_borrow_integration() public {
        aaveLender = new AaveLender();

        aaveLender.depositCollateral{value: 25 ether}(ETH, 25 ether);
        aaveLender.borrowBaseAsset(DAI, 100 ether, 2);
    }

    function test_aave_DAI_deposit_ETH_borrow_integration() public {
        aaveLender = new AaveLender();
        IERC20 dai = IERC20(DAI);

        dai.transfer(address(aaveLender), 5000 ether);
        aaveLender.depositCollateral{value: 0 ether}(DAI, 5000 ether);
        aaveLender.borrowBaseAsset(DAI, 1 ether, 2);
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

    // require for withdraw tests to work
    receive() external payable {}
}
