pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./ElfContracts.sol";

contract ElfContractsTest is DSTest {
    ElfContracts contracts;

    function setUp() public {
        contracts = new ElfContracts();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
