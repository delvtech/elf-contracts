pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "../test/AnAsset.sol";
import "../test/ALender.sol";

import "../test/AToken.sol";
import "../converter/ElementConverter.sol";

import "../funds/low/Elf.sol";

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
    fallback() external payable {}
}

contract ElfContractsTest is DSTest {
    Hevm hevm;
    WETH weth;

    Elf elf;
    ElfStrategy strategy;

    User user1;
    User user2;
    User user3;

    AToken toToken1;
    AToken toToken2;
    AToken toToken3;
    AToken toToken4;

    AnAsset asset1;
    AnAsset asset2;
    AnAsset asset3;
    AnAsset asset4;

    ElementConverter converter1;
    ALender lender1;

    // for testing a basic 4x25% asset percent split
    address[] fromTokens = new address[](4);
    address[] toTokens = new address[](4);
    uint256[] percents = new uint256[](4);
    address[] assets = new address[](4);
    uint256[] conversionType = new uint256[](4);

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        weth = new WETH();

        uint256 numAllocations = uint256(4);

        elf = new Elf(address(weth));
        strategy = new ElfStrategy(address(elf), address(weth));
        toToken1 = new AToken(address(strategy));
        converter1 = new ElementConverter(address(weth));
        lender1 = new ALender(address(converter1), address(weth));
        asset1 = new AnAsset(address(strategy), address(toToken1));
        asset2 = new AnAsset(address(strategy), address(toToken1));
        asset3 = new AnAsset(address(strategy), address(toToken1));
        asset4 = new AnAsset(address(strategy), address(toToken1));

        elf.setStrategy(address(strategy));
        strategy.setConverter(address(converter1));
        converter1.setLender(address(lender1));

        fromTokens[0] = address(weth);
        fromTokens[1] = address(weth);
        fromTokens[2] = address(weth);
        fromTokens[3] = address(weth);

        toTokens[0] = address(toToken1);
        toTokens[1] = address(toToken1);
        toTokens[2] = address(toToken1);
        toTokens[3] = address(toToken1);

        percents[0] = uint256(25);
        percents[1] = uint256(25);
        percents[2] = uint256(25);
        percents[3] = uint256(25);

        assets[0] = address(asset1);
        assets[1] = address(asset2);
        assets[2] = address(asset3);
        assets[3] = address(asset4);

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

        user1 = new User();
        user2 = new User();
        user3 = new User();

        address(user1).transfer(1000 ether);
        address(user2).transfer(1000 ether);
        address(user3).transfer(1000 ether);
        address(lender1).transfer(1000 ether);

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
            address(toToken1),
            keccak256(abi.encode(address(lender1), uint256(0))), // Mint lender 1 1000 toTokens
            bytes32(uint256(1000 ether))
        );
    }

    function test_correctUserBalances() public {
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
        assertEq(toToken1.balanceOf(address(lender1)), 1000 ether);
    }

    function test_depositingETH() public {
        user1.call_depositETH(address(elf), 1 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 1 ether);
        assertEq(toToken1.balanceOf(address(asset1)), 250 finney);
        assertEq(toToken1.balanceOf(address(asset2)), 250 finney);
        assertEq(toToken1.balanceOf(address(asset3)), 250 finney);
        assertEq(toToken1.balanceOf(address(asset4)), 250 finney);
        assertEq(elf.totalSupply(), 1 ether);
        assertEq(elf.balance(), 1 ether);
    }

    function test_depositingWETH() public {
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 1 ether);
        assertEq(toToken1.balanceOf(address(asset1)), 250 finney);
        assertEq(toToken1.balanceOf(address(asset2)), 250 finney);
        assertEq(toToken1.balanceOf(address(asset3)), 250 finney);
        assertEq(toToken1.balanceOf(address(asset4)), 250 finney);
        assertEq(elf.totalSupply(), 1 ether);
        assertEq(elf.balance(), 1 ether);
    }

    function test_multipleETHDeposits() public {
        user1.call_depositETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 1 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 1 ether);
        assertEq(toToken1.balanceOf(address(asset1)), 250 finney);
        assertEq(toToken1.balanceOf(address(asset2)), 250 finney);
        assertEq(toToken1.balanceOf(address(asset3)), 250 finney);
        assertEq(toToken1.balanceOf(address(asset4)), 250 finney);
        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        user2.call_depositETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 2 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 2 ether);
        assertEq(toToken1.balanceOf(address(asset1)), 500 finney);
        assertEq(toToken1.balanceOf(address(asset2)), 500 finney);
        assertEq(toToken1.balanceOf(address(asset3)), 500 finney);
        assertEq(toToken1.balanceOf(address(asset4)), 500 finney);
        assertEq(elf.balance(), 2 ether);
        assertEq(elf.balanceOf(address(user2)), 1 ether);

        user3.call_depositETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 3 ether);
        assertEq(toToken1.balanceOf(address(asset1)), 750 finney);
        assertEq(toToken1.balanceOf(address(asset2)), 750 finney);
        assertEq(toToken1.balanceOf(address(asset3)), 750 finney);
        assertEq(toToken1.balanceOf(address(asset4)), 750 finney);
        assertEq(elf.balance(), 3 ether);
        assertEq(elf.balanceOf(address(user3)), 1 ether);
    }

    function test_multipleWETHDeposits() public {
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 1 ether);
        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        user2.approve(address(weth), address(elf));
        user2.call_deposit(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 2 ether);
        assertEq(elf.balance(), 2 ether);
        assertEq(elf.balanceOf(address(user2)), 1 ether);

        user3.approve(address(weth), address(elf));
        user3.call_deposit(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(elf.balance(), 3 ether);
        assertEq(elf.balanceOf(address(user3)), 1 ether);
    }

    function test_multipleWETHDepositsAndWithdraws() public {
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);

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
        assertEq(toToken1.balanceOf(address(lender1)), 997 ether);

        user1.call_withdraw(address(elf), 1 ether);
        user2.call_withdraw(address(elf), 1 ether);
        user3.call_withdraw(address(elf), 1 ether);

        assertEq(elf.totalSupply(), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 0 ether);
        assertEq(toToken1.balanceOf(address(lender1)), 1000 ether);

        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
    }

    function test_multipleETHDepositsAndWithdraws() public {
        assertEq(address(user1).balance, 1000 ether);
        assertEq(address(user2).balance, 1000 ether);
        assertEq(address(user3).balance, 1000 ether);

        user1.call_depositETH(address(elf), 1 ether);
        user2.call_depositETH(address(elf), 1 ether);
        user3.call_depositETH(address(elf), 1 ether);

        assertEq(address(user1).balance, 999 ether);
        assertEq(address(user2).balance, 999 ether);
        assertEq(address(user3).balance, 999 ether);

        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(lender1)), 3 ether);
        assertEq(toToken1.balanceOf(address(lender1)), 997 ether);

        user1.call_withdrawETH(address(elf), 1 ether);
        user2.call_withdrawETH(address(elf), 1 ether);
        user3.call_withdrawETH(address(elf), 1 ether);

        assertEq(elf.totalSupply(), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 0 ether);
        assertEq(toToken1.balanceOf(address(lender1)), 1000 ether);

        assertEq(address(user1).balance, 1000 ether);
        assertEq(address(user2).balance, 1000 ether);
        assertEq(address(user3).balance, 1000 ether);
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

    // require for withdraw tests to work
    fallback() external payable {}
}
