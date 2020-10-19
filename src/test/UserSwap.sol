pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../libraries/Address.sol";

import "../test/AUserSwap.sol";

import "../user-swaps/ElementUserSwaps.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract ElfContractsTest is DSTest {
    Hevm hevm;
    ElementUserSwaps swapper;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        AUserSwap swapperAddress = new AUserSwap();
        swapper = new ElementUserSwaps(address(swapperAddress));
    }
    
    function testSwap() public {
        (uint a, uint b) = swapper.swapExactAmountIn(address(0x1), 1,  address(0x2), 1, 1);
        (uint c, uint d) = swapper.swapExactAmountOut(address(0x3), 1,  address(0x4), 1, 1);
        assertTrue(true);
        assertEq(a, 1);
        assertEq(b, 1);
        assertEq(c, 1);
        assertEq(d, 1);
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
