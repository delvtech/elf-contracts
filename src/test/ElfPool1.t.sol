// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";

import "../libraries/ERC20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AYVault.sol";
import "./AToken.sol";
import "./ElfDeploy.sol";
import "./WETH.sol";

import "../assets/YVaultAssetProxy.sol";
import "../Elf.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract User {
    // max uint approve for spending
    function approve(address _token, address _guy) public {
        IERC20(_token).approve(_guy, uint256(-1));
    }

    // depositing WETH and minting
    function call_deposit(address _obj, uint256 _amount) public {
        Elf(_obj).deposit(address(this), _amount);
    }

    // withdraw specific shares to WETH
    function call_withdraw(address _obj, uint256 _amount) public {
        Elf(_obj).withdraw(address(this), _amount);
    }

    function call_transfer(
        address _obj,
        address _guy,
        uint256 _amount
    ) public {
        IERC20(_obj).transfer(_guy, _amount);
    }

    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

/// @author Element Finance
/// @title Elf Contract Test
contract ElfContractsTest is DSTest {
    Hevm public hevm;
    WETH public weth;

    Elf public elf;

    User public user1;
    User public user2;
    User public user3;

    AToken public usdc;
    AYVault public yusdc;
    YVaultAssetProxy public yusdcAsset;

    ElfDeploy public elfDeploy;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        elfDeploy = new ElfDeploy();
        elfDeploy.init();

        elfDeploy.config();

        elf = elfDeploy.elf();

        usdc = elfDeploy.usdc();
        yusdc = elfDeploy.yusdc();
        yusdcAsset = elfDeploy.yusdcAsset();

        // create 3 users and provide funds
        user1 = new User();
        usdc.mint(address(user1), 6e6);
        user1.approve(address(usdc), address(elf));
        user2 = new User();
        usdc.mint(address(user2), 6e6);
        user2.approve(address(usdc), address(elf));
        user3 = new User();
        usdc.mint(address(user3), 6e6);
        user3.approve(address(usdc), address(elf));
    }

    /// @notice verify that this can only be changed by governance contract
    function testFail_setGovernance() public {
        elf.setGovernance(address(this));
    }

    /// @notice verify governance can be updated correctly
    function test_setGovernance() public {
        elfDeploy.changeGovernance(address(this));
        assertTrue(elf.governance() == address(this));
    }

    /// @notice test deposit and withdraw integration test
    function test_depositAndWithdraw() public {
        // Set up contracts for the test
        elfDeploy.changeGovernance(address(this));
        assertTrue(elf.governance() == address(this));
        yusdcAsset.setPool(address(elf));

        // Test deposits
        user1.call_deposit(address(elf), 1e6);
        assertEq(elf.balanceOf(address(user1)), 1e6);
        user2.call_deposit(address(elf), 2e6);
        assertEq(elf.balanceOf(address(user2)), 2e6);
        user1.call_deposit(address(elf), 1e6);
        assertEq(elf.balanceOf(address(user1)), 2e6);
        user3.call_deposit(address(elf), 6e6);
        assertEq(elf.balanceOf(address(user3)), 6e6);

        /* At this point:
         * User 1: 2 USDC deposited
         * user 2: 2 USDC deposited
         * User 3: 6 USDC deposited
         */

        // Update vault to 1 share = 1.1 USDC
        yusdc.updateShares();

        // Test a transfer
        user3.call_transfer(address(elf), address(user1), 5e6);
        assertEq(elf.balanceOf(address(user1)), 7e6);

        /* At this point:
         * User 1: 7 shares
         * user 2: 2 shares
         * User 3: 1 shares
         * These shares are worth 11 USDC
         */

        // Test withdraws
        user1.call_withdraw(address(elf), 1e6);
        assertEq(elf.balanceOf(address(user1)), 6e6);

        user1.call_withdraw(address(elf), elf.balanceOf(address(user1)));
        assertEq(elf.balanceOf(address(user1)), 0);

        user2.call_withdraw(address(elf), elf.balanceOf(address(user2)));
        assertEq(elf.balanceOf(address(user2)), 0);

        user3.call_withdraw(address(elf), elf.balanceOf(address(user3)));
        assertEq(elf.balanceOf(address(user3)), 0);

        // make sure we got all our USDC back and then the extra from an increased pricePerFullShare
        uint256 totalBal = usdc.balanceOf(address(user3)) +
            usdc.balanceOf(address(user2)) +
            usdc.balanceOf(address(user1));
        assertEq(totalBal, 19000000);
    }

    /// @notice test that we get the correct balance from elf pool
    function test_balance() public {
        elfDeploy.changeGovernance(address(this));
        assertTrue(elf.governance() == address(this));
        yusdcAsset.setPool(address(elf));

        user1.call_deposit(address(elf), 1e6);
        assertEq(elf.balanceOf(address(user1)), 1e6);

        assertEq(elf.balance(), 1e6);
    }

    /// @notice test that we get the correct underlying balance from elf pool
    function test_balanceUnderlying() public {
        elfDeploy.changeGovernance(address(this));
        assertTrue(elf.governance() == address(this));
        yusdcAsset.setPool(address(elf));

        user1.call_deposit(address(elf), 1e6);
        assertEq(elf.balanceOf(address(user1)), 1e6);

        assertEq(elf.balanceUnderlying(), 1e6);
    }
}
