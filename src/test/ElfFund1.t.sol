pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "../test/AnAsset.sol";
import "../converter/ElementConverter.sol";

import "../funds/low/Elf.sol";

interface Hevm {
    function warp(uint) external;
    function store(address, bytes32, bytes32) external;
}

contract User {

    // max uint approve for spending
    function approve(address _token, address _guy) public {
        IERC20(_token).approve(_guy, uint(-1));
    }

    // depositing WETH and minting
    function call_deposit(address payable _obj, uint _amount) public {
        Elf(_obj).deposit(_amount);
    }

    // deposith ETH, converting to WETH, and minting
    function call_depositETH(address payable _obj) public payable {
        Elf(_obj).depositETH{value: msg.value}();
    }

    // withdraw specific shares
    function call_withdraw(address payable _obj, uint _amount) public {
        Elf(_obj).withdraw(_amount);
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

    AnAsset fromAsset1;
    AnAsset fromAsset2;
    AnAsset fromAsset3;
    AnAsset fromAsset4;

    AnAsset toAsset1;
    AnAsset toAsset2;
    AnAsset toAsset3;
    AnAsset toAsset4;

    ElementConverter converter1;
    ElementConverter converter2;
    ElementConverter converter3;
    ElementConverter converter4;

    // for testing a basic 4x25% asset percent split
    address[] fromAssets = new address[](4);
    address[] toAssets = new address[](4);
    uint256[] percents = new uint256[](4);
    uint256[] conversionType = new uint256[](4);
    uint256[] implementation = new uint256[](4);

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        weth = new WETH();

        uint256 numAllocations = uint256(4);

        elf         = new Elf(address(weth));
        strategy    = new ElfStrategy(address(elf), address(weth));
        converter1  = new ElementConverter();
        fromAsset1  = new AnAsset(address(strategy));
        toAsset1  = new AnAsset(address(strategy));

        elf.setStrategy(address(strategy));
        strategy.setConverter(address(converter1));

        fromAssets[0] = address(fromAsset1);
        fromAssets[1] = address(fromAsset1);
        fromAssets[2] = address(fromAsset1);
        fromAssets[3] = address(fromAsset1);

        toAssets[0] = address(toAsset1);
        toAssets[1] = address(toAsset1);
        toAssets[2] = address(toAsset1);
        toAssets[3] = address(toAsset1);

        percents[0] = uint256(25);
        percents[1] = uint256(25);
        percents[2] = uint256(25);
        percents[3] = uint256(25);

        conversionType[0] = uint256(0);
        conversionType[1] = uint256(0);
        conversionType[2] = uint256(0);
        conversionType[3] = uint256(0);

        implementation[0] = uint256(0);
        implementation[1] = uint256(0);
        implementation[2] = uint256(0);
        implementation[3] = uint256(0);

        strategy.setAllocations(fromAssets, toAssets, percents, conversionType, implementation, numAllocations);

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
    }

    function test_correctUserBalances() public {
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
    }


    function test_depositingETH() public {

        // user1 deposits 1 ether to the elf
        user1.call_depositETH{value: 1 ether}(address(elf));
        // weth balance of the fund is zero
        assertEq(weth.balanceOf(address(this)), 0 ether);
        // weth balance of the strategy is 1 (it was invest()'ed)
        assertEq(weth.balanceOf(address(strategy)), 1 ether);
        // totalSupply is now equal to 1 ether
        assertEq(elf.totalSupply(), 1 ether);
        // balance() is now equal to 1 ether
        assertEq(elf.balance(), 1 ether);
    }

    function test_depositingWETH() public {
        // user1 deposits 1 ether to the elf
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        // weth balance of the fund is zero
        assertEq(weth.balanceOf(address(this)), 0 ether);
        // weth balance of the strategy is 1 (it was invest()'ed)
        assertEq(weth.balanceOf(address(strategy)), 1 ether);
        // totalSupply is now equal to 1 ether
        assertEq(elf.totalSupply(), 1 ether);
        // balance() is now equal to 1 ether
        assertEq(elf.balance(), 1 ether);
    }

    function test_multipleETHDeposits() public {
        // user1 deposits 1 ether to the elf
        user1.call_depositETH{value: 1 ether}(address(elf));
        // totalSupply is now equal to 1 ether
        assertEq(elf.totalSupply(), 1 ether);
        // balance() is now equal to 1 ether
        assertEq(elf.balance(), 1 ether);
        // user fund token balance is now 1 ether
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        // user2 deposits 1 ether to the elf, but because that's only 50% the pool, they input 0.5 ether (in units)
        user2.call_depositETH.value(1 ether)(address(elf));
        // totalSupply is now 2 ether
        assertEq(elf.totalSupply(), 2 ether);
        assertEq(elf.balance(), 2 ether);
        assertEq(elf.balanceOf(address(user2)), 1 ether);

        // user3 deposits 1 ether to the elf, but because that's only 50% the pool, they input 0.5 ether (in units)
        user3.call_depositETH.value(1 ether)(address(elf));
        // totalSupply is now 2 ether 
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(elf.balance(), 3 ether);
        assertEq(elf.balanceOf(address(user3)), 1 ether);
    }

    function test_multipleWETHDeposits() public {
        // user1 deposits 1 ether to the elf
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        // totalSupply is now equal to 1 ether
        assertEq(elf.totalSupply(), 1 ether);
        // balance() is now equal to 1 ether
        assertEq(elf.balance(), 1 ether);
        // user fund token balance is now 1 ether
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        // user2 deposits 1 ether to the elf, but because that's only 50% the pool, they input 0.5 ether (in units)
        user2.approve(address(weth), address(elf));
        user2.call_deposit(address(elf), 1 ether);
        // totalSupply is now 2 ether
        assertEq(elf.totalSupply(), 2 ether);
        assertEq(elf.balance(), 2 ether);
        assertEq(elf.balanceOf(address(user2)), 1 ether);

        // user3 deposits 1 ether to the elf, but because that's only 50% the pool, they input 0.5 ether (in units)
        user3.approve(address(weth), address(elf));
        user3.call_deposit(address(elf), 1 ether);
        // totalSupply is now 2 ether 
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(elf.balance(), 3 ether);
        assertEq(elf.balanceOf(address(user3)), 1 ether);
    }

    function test_multipleDepositsAndWithdraw() public {
        user1.call_depositETH{value: 1 ether}(address(elf));
        user2.call_depositETH{value: 1 ether}(address(elf));
        user3.call_depositETH{value: 1 ether}(address(elf));

        assertEq(elf.totalSupply(), 3 ether);

        user1.call_withdraw(address(elf), 1 ether);
        user2.call_withdraw(address(elf), 1 ether);
        user3.call_withdraw(address(elf), 1 ether);

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
