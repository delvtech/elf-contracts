pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "../lenders/compound/CompoundLender.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract Test {
    function supplyEthToCompound()
        public
        payable
    {
        // Create a reference to the corresponding cToken contract
        ICEth cToken = ICEth(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);

        cToken.mint.value(msg.value).gas(250000)();
    }
}

contract CompLenderTest is DSTest {
    Hevm public hevm;
    APriceOracle public price;
    IWETH public weth;
    CompLender public comp;
    IERC20 public usdc;
    Test public t;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        price = new APriceOracle();
        t = new Test();

        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        hevm.store(
            address(weth),
            keccak256(abi.encode(address(this), uint256(3))), // Mint us 1000 WETH
            bytes32(uint256(1000 ether))
        );

        assertEq(weth.balanceOf(address(this)), 1000 ether);

        weth.withdraw(10 ether);
        t.supplyEthToCompound{value: 1 ether}();

        comp = new CompLender(address(price), address(this));
        usdc = IERC20(comp.USDC());
        weth.transfer(address(comp), 10 ether);
    }

    function test_draw() public {
        // comp.depositAndBorrow();
        // assertTrue(usdc.balanceOf(address(this)) == 0);
    }

    receive() external payable {}
}