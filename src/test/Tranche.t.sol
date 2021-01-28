// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";

import "../libraries/ERC20.sol";

import "../Tranche.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract User {
    function approve(address _token, address _spender) public {
        IERC20(_token).approve(_spender, type(uint256).max);
    }

    function call_deposit(Tranche _obj, uint256 _amount) public {
        _obj.deposit(_amount);
    }

    function call_withdraw_yc(Tranche _obj, uint256 _amount) public {
        _obj.withdrawYc(_amount);
    }

    function call_withdraw_fyt(Tranche _obj, uint256 _amount) public {
        _obj.withdrawFyt(_amount);
    }
}

contract ElfStub is ERC20 {
    uint256 public underlyingUnitValue = 100;

    // solhint-disable-next-line no-empty-blocks
    constructor() ERC20("ELement Finance", "TestELF") {}

    function setSharesToUnderlying(uint256 _value) external {
        underlyingUnitValue = _value;
    }

    function getSharesToUnderlying(uint256 _shares)
        external
        view
        returns (uint256)
    {
        return _shares * underlyingUnitValue;
    }

    function balanceOfUnderlying(address who) external view returns (uint256) {
        return balanceOf(who) * underlyingUnitValue;
    }

    function mint(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }
}

contract TrancheTest is DSTest {
    Hevm public hevm;
    ElfStub public elfStub;
    Tranche public tranche;
    IERC20 public yc;

    User public user1;
    User public user2;
    User public user3;

    uint256 public timestamp;
    uint256 public lockDuration;
    uint256 public initialBalance = 2e9;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        timestamp = block.timestamp;
        lockDuration = 5000000; //seconds
        elfStub = new ElfStub();
        tranche = new Tranche(address(elfStub), lockDuration);
        yc = tranche.yc();

        // 2 mock users
        user1 = new User();
        elfStub.mint(address(user1), initialBalance);
        user1.approve(address(elfStub), address(tranche));

        user2 = new User();
        elfStub.mint(address(user2), initialBalance);
        user2.approve(address(elfStub), address(tranche));
    }

    // verify that this can only be changed by governance contract
    function testFail_deposit_afterTimeout() public {
        hevm.warp(timestamp + lockDuration);
        user1.call_deposit(tranche, initialBalance);
    }

    // verify that this can only be changed by governance contract
    function testFail_deposit_overfund() public {
        user1.call_deposit(tranche, initialBalance + 1);
    }

    function test_deposit_no_interest() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(tranche, initialBalance);
        user2.call_deposit(tranche, initialBalance);

        assertEq(yc.balanceOf(address(user1)), initialBalance);
        assertEq(
            tranche.balanceOf(address(user1)),
            initialBalance * initialUnderlying
        );
        assertEq(yc.balanceOf(address(user2)), initialBalance);
        assertEq(
            tranche.balanceOf(address(user2)),
            initialBalance * initialUnderlying
        );
        assertEq(elfStub.balanceOf(address(user1)), 0);
        assertEq(elfStub.balanceOf(address(user2)), 0);
    }

    function test_deposit_interest() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();
        user1.call_deposit(tranche, initialBalance);

        // pool has accumulated 20% interest
        elfStub.setSharesToUnderlying(
            initialUnderlying + ((initialUnderlying * 20) / 100)
        );

        user2.call_deposit(tranche, initialBalance);

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(yc.balanceOf(address(user1)), initialBalance);
        assertEq(
            tranche.balanceOf(address(user1)),
            initialBalance * initialUnderlying
        );
        assertEq(yc.balanceOf(address(user2)), initialBalance);
        assertEq(
            tranche.balanceOf(address(user2)),
            initialBalance * initialUnderlying
        );
    }

    function test_withdraw_fyt_no_interest() public {
        user1.call_deposit(tranche, initialBalance);
        user2.call_deposit(tranche, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_fyt(tranche, tranche.balanceOf(address(user1)));
        user2.call_withdraw_fyt(tranche, tranche.balanceOf(address(user2)));

        assertEq(elfStub.balanceOf(address(user1)), initialBalance);
        assertEq(elfStub.balanceOf(address(user2)), initialBalance);
    }

    function test_withdraw_fyt_interest() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(tranche, initialBalance);

        elfStub.setSharesToUnderlying(
            initialUnderlying + ((initialUnderlying * 20) / 100)
        );

        user2.call_deposit(tranche, initialBalance);

        hevm.warp(timestamp + lockDuration);
        elfStub.setSharesToUnderlying(
            initialUnderlying + ((initialUnderlying * 20) / 100)
        );

        user1.call_withdraw_fyt(tranche, tranche.balanceOf(address(user1)));
        user2.call_withdraw_fyt(tranche, tranche.balanceOf(address(user2)));

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
    }

    function test_withdraw_yc_no_interest() public {
        user1.call_deposit(tranche, initialBalance);
        user2.call_deposit(tranche, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_yc(tranche, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(tranche, yc.balanceOf(address(user2)));

        assertEq(elfStub.balanceOf(address(user1)), 0);
        assertEq(elfStub.balanceOf(address(user2)), 0);
    }

    function test_withdraw_yc_interest() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(tranche, initialBalance);

        elfStub.setSharesToUnderlying(
            initialUnderlying + ((initialUnderlying * 20) / 100)
        );

        user2.call_deposit(tranche, initialBalance);

        hevm.warp(timestamp + lockDuration);
        elfStub.setSharesToUnderlying(
            initialUnderlying + ((initialUnderlying * 20) / 100)
        );

        user1.call_withdraw_yc(tranche, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(tranche, yc.balanceOf(address(user2)));

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
    }

    function test_withdraw_all_no_interest_1() public {
        user1.call_deposit(tranche, initialBalance);
        user2.call_deposit(tranche, initialBalance);

        hevm.warp(timestamp + lockDuration);
        user1.call_withdraw_yc(tranche, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(tranche, yc.balanceOf(address(user2)));
        user1.call_withdraw_fyt(tranche, tranche.balanceOf(address(user1)));
        user2.call_withdraw_fyt(tranche, tranche.balanceOf(address(user2)));

        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        assertEq(tranche.totalSupply(), 0);
        assertEq(yc.totalSupply(), 0);
        assertEq(elfStub.balanceOf(address(tranche)), 0);
    }

    function test_withdraw_all_no_interest_2() public {
        user1.call_deposit(tranche, initialBalance);
        user2.call_deposit(tranche, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_fyt(tranche, tranche.balanceOf(address(user1)));
        user2.call_withdraw_fyt(tranche, tranche.balanceOf(address(user2)));
        user1.call_withdraw_yc(tranche, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(tranche, yc.balanceOf(address(user2)));

        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        assertEq(tranche.totalSupply(), 0);
        assertEq(yc.totalSupply(), 0);
        assertEq(elfStub.balanceOf(address(tranche)), 0);
    }

    function test_withdraw_all_interest_1() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(tranche, initialBalance);

        elfStub.setSharesToUnderlying(initialUnderlying * 2);

        user2.call_deposit(tranche, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_yc(tranche, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(tranche, yc.balanceOf(address(user2)));
        user1.call_withdraw_fyt(tranche, tranche.balanceOf(address(user1)));
        user2.call_withdraw_fyt(tranche, tranche.balanceOf(address(user2)));

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        assertEq(tranche.totalSupply(), 0);
        assertEq(yc.totalSupply(), 0);
        assertEq(elfStub.balanceOf(address(tranche)), 0);
    }

    function test_withdraw_all_interest_2() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(tranche, initialBalance);

        elfStub.setSharesToUnderlying(initialUnderlying * 2);

        user2.call_deposit(tranche, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_fyt(tranche, tranche.balanceOf(address(user1)));
        user2.call_withdraw_fyt(tranche, tranche.balanceOf(address(user2)));
        user1.call_withdraw_yc(tranche, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(tranche, yc.balanceOf(address(user2)));

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        assertEq(tranche.totalSupply(), 0);
        assertEq(yc.totalSupply(), 0);
        assertEq(elfStub.balanceOf(address(tranche)), 0);
    }

    function test_withdraw_all_negative_interest_1() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(tranche, initialBalance);
        user2.call_deposit(tranche, initialBalance);

        elfStub.setSharesToUnderlying((initialUnderlying * 90) / 100);

        hevm.warp(timestamp + lockDuration);
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        user1.call_withdraw_fyt(tranche, tranche.balanceOf(address(user1)));
        user2.call_withdraw_fyt(tranche, tranche.balanceOf(address(user2)));
        user1.call_withdraw_yc(tranche, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(tranche, yc.balanceOf(address(user2)));
        assertEq(yc.totalSupply(), 0);
        assertEq(tranche.totalSupply(), 0);
    }

    function test_withdraw_all_negative_interest_2() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(tranche, initialBalance);
        user2.call_deposit(tranche, initialBalance);

        elfStub.setSharesToUnderlying((initialUnderlying * 90) / 100);

        hevm.warp(timestamp + lockDuration);
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        user1.call_withdraw_yc(tranche, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(tranche, yc.balanceOf(address(user2)));
        user1.call_withdraw_fyt(tranche, tranche.balanceOf(address(user1)));
        user2.call_withdraw_fyt(tranche, tranche.balanceOf(address(user2)));

        assertEq(yc.totalSupply(), 0);
        assertEq(tranche.totalSupply(), 0);
    }
}
