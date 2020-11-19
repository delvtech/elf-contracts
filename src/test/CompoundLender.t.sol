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

contract CompLenderTest is DSTest {
    Hevm public hevm;
    IWETH public weth;
    CompLender public comp;
    IERC20 public usdc;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        hevm.store(
            address(weth),
            keccak256(abi.encode(address(this), uint256(3))), // Mint us 1000 WETH
            bytes32(uint256(1000 ether))
        );

        assertEq(weth.balanceOf(address(this)), 1000 ether);

        comp = new CompLender(address(this));
        usdc = IERC20(comp.USDC());
        weth.transfer(address(comp), 10 ether);
        usdc.approve(address(comp), 1000000000000000);
        weth.withdraw(10 ether);
        comp.cETH().mint{value: 10 ether}();
    }

    function test_integration() public {
        uint256 usdcBal = usdc.balanceOf(address(this));

        // Deposit WETH and borrow USDC
        comp.depositAndBorrow();
        assertTrue(usdc.balanceOf(address(this)) > usdcBal);
        usdcBal = usdc.balanceOf(address(this));

        uint256 debt = comp.getTotalDebtAmount();
        assertTrue(debt > 0);

        // Withdraw half our WETH and pay back USDC
        comp.withdraw(5 ether);
        assertTrue(usdc.balanceOf(address(this)) < usdcBal);
        usdcBal = usdc.balanceOf(address(this));

        weth.transfer(address(comp), 10 ether);
        comp.depositAndBorrow();
        assertTrue(usdc.balanceOf(address(this)) > usdcBal);
        usdcBal = usdc.balanceOf(address(this));

        uint256 ratio = comp.getCurrentRatio();
        assertTrue(ratio < 760000000000000000);
        assertTrue(ratio > 740000000000000000);

        // assertTrue(!comp.shouldDraw());

        // // Set ETH price
        // hevm.store(
        //     address(0x922018674c12a7F0D394ebEEf9B58F186CdE13c1),
        //     keccak256(abi.encode(keccak256("ETH"), uint256(0))), // Mint us 1000 WETH
        //     bytes32(uint256(500e6))
        // );

        // assertTrue(!comp.shouldDraw());
        // assertTrue(comp.shouldDrawCurrent());
        // assertTrue(comp.shouldDraw());
    }

    receive() external payable {}
}