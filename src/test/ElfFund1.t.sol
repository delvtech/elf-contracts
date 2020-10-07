pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "../test/AnAsset.sol";
import "../test/AConverter.sol";

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

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        weth = new WETH();

        elf = new Elf(address(weth));
        strategy = new ElfStrategy(address(elf), address(weth));
        elf.setStrategy(address(strategy));

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

    function test_generalDeposits() public {
        // user1 deposits 1 ether to the elf
        user1.call_depositETH{value: 1 ether}(address(elf));
        // totalSupply is now equal to 1 ether
        assertEq(elf.totalSupply(), 1 ether);
        // balance() is now equal to 1 ether
        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(user1)), 1337);

        // user2 deposits 1 ether to the elf, but because that's only 50% the pool, they input 0.5 ether (in units)
        user2.call_depositETH.value(1 ether)(address(elf));
        // totalSupply is now 2 ether
        assertEq(elf.totalSupply(), 2 ether);
        assertEq(elf.balance(), 2 ether);
        assertEq(elf.balanceOf(address(user2)), 1337);

        // user3 deposits 1 ether to the elf, but because that's only 50% the pool, they input 0.5 ether (in units)
        user3.call_depositETH.value(1 ether)(address(elf));
        // totalSupply is now 2 ether 
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(elf.balance(), 3 ether);
        assertEq(elf.balanceOf(address(user3)), 1337);


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

    // function test_DepositWithdraw() public {
    //     // Create Strategy for Elf
    //     // assertEq(elf.governance(), address(this));
    //     // ElfStrategy strategy = new ElfStrategy(address(elf));
    //     // elf.setStrategy(address(strategy));

    //     // Create Allocations for Strategy
    //     AnAsset asset1 = new AnAsset(address(strategy));
    //     address[] memory assets = new address[](4);
    //     assets[0] = address(asset1);
    //     assets[1] = address(asset1);
    //     assets[2] = address(asset1);
    //     assets[3] = address(asset1);
    //     uint256[] memory percents = new uint256[](4);
    //     percents[0] = uint256(25);
    //     percents[1] = uint256(25);
    //     percents[2] = uint256(25);
    //     percents[3] = uint256(25);
    //     uint256 numAllocations = uint256(4);
    //     strategy.setAllocations(assets, percents, numAllocations);

    //     // create a Converter for Strategy
    //     AConverter converter = new AConverter();
    //     AnAsset asset2 = new AnAsset(address(converter));
    //     converter.setAsset(address(asset2));
    //     strategy.setConverter(address(converter));

    //     // first call to deposit()
    //     elf.deposit.value(1 ether)();

    //     // balance is 1 ether because 1 ether has been invested() to the strategy
    //     assertEq(elf.balance(), 1 ether);

    //     // withdraw
    //     elf.withdraw(1 ether);

    //     assertEq(elf.balance(), 0 ether);
    //     assertEq(elf.balanceOf(address(this)), 0 ether);

    //     // second call to deposit()
    //     elf.deposit.value(1 ether)();

    //     assertEq(elf.balance(), 1 ether);
    //     assertEq(elf.balanceOf(address(this)), 1 ether);

    //     // withdraw again
    //     elf.withdraw(1 ether);

    //     assertEq(elf.balance(), 0 ether);
    //     assertEq(elf.balanceOf(address(this)), 0 ether);
    // }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

    // require for withdraw tests to work
    fallback() external payable {}
}
