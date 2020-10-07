pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";
import "../interfaces/ERC20.sol";

import "../test/AnAsset.sol";
import "../test/AConverter.sol";

import "../funds/low/Elf.sol";

interface Hevm {
    function warp(uint) external;
    function store(address, bytes32, bytes32) external;
}

contract User {

    function call_deposit(address payable obj) public payable {
        Elf(obj).deposit{value: msg.value}();
        // Elf(obj).deposit.value(msg.value)();
    }

    function call_withdraw(address payable obj, uint _amount) public {
        Elf(obj).withdraw(_amount);
    }

    // to be able to receive funds
    fallback() external payable {}
}

contract ElfContractsTest is DSTest {
    Hevm hevm;

    Elf elf;
    ElfStrategy strategy;

    User user1;
    User user2;
    User user3;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        elf = new Elf();
        strategy = new ElfStrategy(address(elf));
        elf.setStrategy(address(strategy));

        user1 = new User();
        user2 = new User();
        user3 = new User();

        address(user1).transfer(1000 ether);
        address(user2).transfer(1000 ether);
        address(user3).transfer(1000 ether);
    }

    function test_generalDeposits() public {
        // user1 deposits 1 ether to the elf
        user1.call_deposit.value(1 ether)(address(elf));
        // totalSupply is now equal to 1 ether
        assertEq(elf.totalSupply(), 1 ether);
        // balance() is now equal to 1 ether
        assertEq(elf.balance(), 1 ether);

        // user2 deposits 1 ether to the elf, but because that's only 50% the pool, they input 0.5 ether (in units)
        user2.call_deposit.value(1 ether)(address(elf));
        // totalSupply is now 1.5 ether 
        assertEq(elf.totalSupply(), 1.5 ether);

        user3.call_deposit.value(1 ether)(address(elf));
        // totalSupply is now 2 ether
        assertEq(elf.totalSupply(), 2 ether);

        // token in Elf not yet performing WETH transfer/withdraw
        // assertEq(address(user1).balance, 999 ether);
        // assertEq(address(user2).balance, 999 ether);
        // assertEq(address(user3).balance, 999 ether);
    }

    // function test_multipleDeposits() public {
    //     user1.call_deposit.value(1 ether)(address(elf));
    //     user2.call_deposit.value(1 ether)(address(elf));
    //     user3.call_deposit.value(1 ether)(address(elf));

    //     assertEq(elf.totalSupply(), 2 ether);

    //     assertEq(address(user1).balance, 999 ether);
    //     assertEq(address(user2).balance, 999 ether);
    //     assertEq(address(user3).balance, 999 ether);
    // }

    // function test_multipleDepositsAndWithdraw() public {
    //     user1.call_deposit.value(1 ether)(address(elf));
    //     user2.call_deposit.value(1 ether)(address(elf));
    //     user3.call_deposit.value(1 ether)(address(elf));

    //     assertEq(elf.totalSupply(), 2 ether);

    //     user1.call_withdraw(address(elf), 1 ether);
    //     user2.call_withdraw(address(elf), 1 ether);
    //     user3.call_withdraw(address(elf), 1 ether);
    // }

    function test_DepositWithdraw() public {
        // Create Strategy for Elf
        // assertEq(elf.governance(), address(this));
        // ElfStrategy strategy = new ElfStrategy(address(elf));
        // elf.setStrategy(address(strategy));

        // Create Allocations for Strategy
        AnAsset asset1 = new AnAsset(address(strategy));
        address[] memory assets = new address[](4);
        assets[0] = address(asset1);
        assets[1] = address(asset1);
        assets[2] = address(asset1);
        assets[3] = address(asset1);
        uint256[] memory percents = new uint256[](4);
        percents[0] = uint256(25);
        percents[1] = uint256(25);
        percents[2] = uint256(25);
        percents[3] = uint256(25);
        uint256 numAllocations = uint256(4);
        strategy.setAllocations(assets, percents, numAllocations);

        // create a Converter for Strategy
        AConverter converter = new AConverter();
        AnAsset asset2 = new AnAsset(address(converter));
        converter.setAsset(address(asset2));
        strategy.setConverter(address(converter));

        // first call to deposit()
        elf.deposit.value(1 ether)();

        // balance is 1 ether because 1 ether has been invested() to the strategy
        assertEq(elf.balance(), 1 ether);

        // withdraw
        elf.withdraw(1 ether);

        assertEq(elf.balance(), 0 ether);
        assertEq(elf.balanceOf(address(this)), 0 ether);

        // second call to deposit()
        elf.deposit.value(1 ether)();

        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(this)), 1 ether);

        // withdraw again
        elf.withdraw(1 ether);

        assertEq(elf.balance(), 0 ether);
        assertEq(elf.balanceOf(address(this)), 0 ether);
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
