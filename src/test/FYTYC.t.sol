// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";

import "../libraries/ERC20.sol";
import "../libraries/SafeMath.sol";

import "../FYTYC.sol";

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
        IERC20(_token).approve(_spender, uint256(-1));
    }

    function call_deposit(FYTYC _obj, uint256 _amount) public {
        _obj.deposit(_amount);
    }

    function call_withdraw_yc(FYTYC _obj, uint256 _amount) public {
        _obj.withdrawYc(_amount);
    }

    function call_withdraw_fyt(FYTYC _obj, uint256 _amount) public {
        _obj.withdrawFyt(_amount);
    }
}

contract ElfStub is ERC20 {
    uint256 public underlyingUnitValue = 100;

    // solhint-disable-next-line no-empty-blocks
    constructor() public ERC20("ELement Finance", "TestELF") {}

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

    function balanceOfUnderlying(address who) external view returns(uint256) {
        return balanceOf(who)*underlyingUnitValue;
    }

    function mint(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }
}

contract FYTYCTest is DSTest {
    Hevm public hevm;
    ElfStub public elfStub;
    FYTYC public fytyc;
    IERC20 public yc;

    User public user1;
    User public user2;
    User public user3;

    uint256 public timestamp;
    uint256 public lockDuration;
    uint256 public initialBalance = 2e9;

    using SafeMath for uint256;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        timestamp = block.timestamp;
        lockDuration = 5000000; //seconds
        elfStub = new ElfStub();
        fytyc = new FYTYC(address(elfStub), lockDuration);
        yc = fytyc.yc();

        // 2 mock users
        user1 = new User();
        elfStub.mint(address(user1), initialBalance);
        user1.approve(address(elfStub), address(fytyc));

        user2 = new User();
        elfStub.mint(address(user2), initialBalance);
        user2.approve(address(elfStub), address(fytyc));
    }

    // verify that this can only be changed by governance contract
    function testFail_deposit_afterTimeout() public {
        hevm.warp(timestamp + lockDuration);
        user1.call_deposit(fytyc, initialBalance);
    }

    // verify that this can only be changed by governance contract
    function testFail_deposit_overfund() public {
        user1.call_deposit(fytyc, initialBalance + 1);
    }

    function test_deposit_no_interest() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(fytyc, initialBalance);
        user2.call_deposit(fytyc, initialBalance);

        assertEq(yc.balanceOf(address(user1)), initialBalance);
        assertEq(
            fytyc.balanceOf(address(user1)),
            initialBalance.mul(initialUnderlying)
        );
        assertEq(yc.balanceOf(address(user2)), initialBalance);
        assertEq(
            fytyc.balanceOf(address(user2)),
            initialBalance.mul(initialUnderlying)
        );
        assertEq(elfStub.balanceOf(address(user1)), 0);
        assertEq(elfStub.balanceOf(address(user2)), 0);
    }

    function test_deposit_interest() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();
        user1.call_deposit(fytyc, initialBalance);

        // pool has accumulated 20% interest
        elfStub.setSharesToUnderlying(
            initialUnderlying.add(initialUnderlying.mul(20).div(100))
        );

        user2.call_deposit(fytyc, initialBalance);

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(yc.balanceOf(address(user1)), initialBalance);
        assertEq(
            fytyc.balanceOf(address(user1)),
            initialBalance.mul(initialUnderlying)
        );
        assertEq(yc.balanceOf(address(user2)), initialBalance);
        assertEq(
            fytyc.balanceOf(address(user2)),
            initialBalance.mul(initialUnderlying)
        );
    }

    function test_withdraw_fyt_no_interest() public {
        user1.call_deposit(fytyc, initialBalance);
        user2.call_deposit(fytyc, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user1)));
        user2.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user2)));

        assertEq(elfStub.balanceOf(address(user1)), initialBalance);
        assertEq(elfStub.balanceOf(address(user2)), initialBalance);
    }

    function test_withdraw_fyt_interest() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(fytyc, initialBalance);

        elfStub.setSharesToUnderlying(
            initialUnderlying.add(initialUnderlying.mul(20).div(100))
        );

        user2.call_deposit(fytyc, initialBalance);

        hevm.warp(timestamp + lockDuration);
        elfStub.setSharesToUnderlying(
            initialUnderlying.add(initialUnderlying.mul(20).div(100))
        );

        user1.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user1)));
        user2.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user2)));

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
    }

    function test_withdraw_yc_no_interest() public {
        user1.call_deposit(fytyc, initialBalance);
        user2.call_deposit(fytyc, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_yc(fytyc, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(fytyc, yc.balanceOf(address(user2)));

        assertEq(elfStub.balanceOf(address(user1)), 0);
        assertEq(elfStub.balanceOf(address(user2)), 0);
    }

    function test_withdraw_yc_interest() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(fytyc, initialBalance);

        elfStub.setSharesToUnderlying(
            initialUnderlying.add(initialUnderlying.mul(20).div(100))
        );

        user2.call_deposit(fytyc, initialBalance);

        hevm.warp(timestamp + lockDuration);
        elfStub.setSharesToUnderlying(
            initialUnderlying.add(initialUnderlying.mul(20).div(100))
        );

        user1.call_withdraw_yc(fytyc, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(fytyc, yc.balanceOf(address(user2)));

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
    }

    function test_withdraw_all_no_interest_1() public {
        user1.call_deposit(fytyc, initialBalance);
        user2.call_deposit(fytyc, initialBalance);

        hevm.warp(timestamp + lockDuration);
        user1.call_withdraw_yc(fytyc, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(fytyc, yc.balanceOf(address(user2)));
        user1.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user1)));
        user2.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user2)));

        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        assertEq(fytyc.totalSupply(), 0);
        assertEq(yc.totalSupply(), 0);
        assertEq(elfStub.balanceOf(address(fytyc)), 0);
    }

    function test_withdraw_all_no_interest_2() public {
        user1.call_deposit(fytyc, initialBalance);
        user2.call_deposit(fytyc, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user1)));
        user2.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user2)));
        user1.call_withdraw_yc(fytyc, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(fytyc, yc.balanceOf(address(user2)));

        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        assertEq(fytyc.totalSupply(), 0);
        assertEq(yc.totalSupply(), 0);
        assertEq(elfStub.balanceOf(address(fytyc)), 0);
    }

    function test_withdraw_all_interest_1() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(fytyc, initialBalance);

        elfStub.setSharesToUnderlying(initialUnderlying.mul(2));

        user2.call_deposit(fytyc, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_yc(fytyc, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(fytyc, yc.balanceOf(address(user2)));
        user1.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user1)));
        user2.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user2)));

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        assertEq(fytyc.totalSupply(), 0);
        assertEq(yc.totalSupply(), 0);
        assertEq(elfStub.balanceOf(address(fytyc)), 0);
    }

    function test_withdraw_all_interest_2() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(fytyc, initialBalance);

        elfStub.setSharesToUnderlying(initialUnderlying.mul(2));

        user2.call_deposit(fytyc, initialBalance);

        hevm.warp(timestamp + lockDuration);

        user1.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user1)));
        user2.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user2)));
        user1.call_withdraw_yc(fytyc, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(fytyc, yc.balanceOf(address(user2)));

        // given the same ELF token input, the user should always gain the same FYT output.
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        assertEq(fytyc.totalSupply(), 0);
        assertEq(yc.totalSupply(), 0);
        assertEq(elfStub.balanceOf(address(fytyc)), 0);
    }

    function test_withdraw_all_negative_interest_1() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(fytyc, initialBalance);
        user2.call_deposit(fytyc, initialBalance);

        elfStub.setSharesToUnderlying(initialUnderlying.mul(90).div(100));

        hevm.warp(timestamp + lockDuration);
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        user1.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user1)));
        user2.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user2)));
        user1.call_withdraw_yc(fytyc, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(fytyc, yc.balanceOf(address(user2)));
        assertEq(yc.totalSupply(), 0);
        assertEq(fytyc.totalSupply(), 0);
    }

    function test_withdraw_all_negative_interest_2() public {
        uint256 initialUnderlying = elfStub.underlyingUnitValue();

        user1.call_deposit(fytyc, initialBalance);
        user2.call_deposit(fytyc, initialBalance);

        elfStub.setSharesToUnderlying(initialUnderlying.mul(90).div(100));

        hevm.warp(timestamp + lockDuration);
        assertEq(
            elfStub.balanceOf(address(user1)),
            elfStub.balanceOf(address(user2))
        );
        user1.call_withdraw_yc(fytyc, yc.balanceOf(address(user1)));
        user2.call_withdraw_yc(fytyc, yc.balanceOf(address(user2)));
        user1.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user1)));
        user2.call_withdraw_fyt(fytyc, fytyc.balanceOf(address(user2)));

        assertEq(yc.totalSupply(), 0);
        assertEq(fytyc.totalSupply(), 0);
    }
}
