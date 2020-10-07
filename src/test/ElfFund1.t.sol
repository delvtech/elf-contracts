pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/ERC20Interfaces.sol";
import "../test/AnAsset.sol";
import "../test/AConverter.sol";

import "../funds/low/Elf.sol";

contract ElfContractsTest is DSTest {
    Elf elf;

    function setUp() public {
        elf = new Elf();
    }

    function test_DepositWithdraw() public {
        // Create Strategy for Elf
        assertEq(elf.governance(), address(this));
        ElfStrategy strategy = new ElfStrategy(address(elf));
        elf.setStrategy(address(strategy));

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
        elf.withdraw(1);

        assertEq(elf.balance(), 0 ether);
        assertEq(elf.balanceOf(address(this)), 0 ether);

        // second call to deposit()
        elf.deposit.value(1 ether)();

        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(this)), 1);

        // withdraw again
        elf.withdraw(1);

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
