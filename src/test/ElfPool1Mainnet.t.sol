// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";

import "../libraries/ERC20.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AYVault.sol";
import "./AToken.sol";
import "./ElfDeploy.sol";
import "./WETH.sol";

import "../interfaces/YearnVaultV1.sol";

import "../assets/YVaultAssetProxy.sol";
import "../Elf.sol";

interface Hevm {
    function warp(uint256) external;

    function roll(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract User {
    // max uint approve for spending
    function approve(address _token, address _guy) public {
        IERC20(_token).approve(_guy, type(uint256).max);
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
/// @title Elf Contract Mainnet Test
contract ElfContractsTest is DSTest {
    Hevm public hevm;
    WETH public weth;

    User public user1;
    User public user2;
    User public user3;

    IERC20 public usdc;
    YearnVault public yusdc;
    YVaultAssetProxy public yusdcAsset;

    ElfFactory public factory;
    Elf public elf;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        factory = new ElfFactory();

        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        yusdc = YearnVault(0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e);

        yusdcAsset = new YVaultAssetProxy(address(yusdc), address(usdc));

        elf = factory.newPool(address(usdc), address(yusdcAsset));

        // create 3 users and provide funds through HEVM store
        user1 = new User();
        hevm.store(
            address(usdc),
            keccak256(abi.encode(address(user1), uint256(9))),
            bytes32(uint256(200000000000))
        );
        user1.approve(address(usdc), address(elf));

        user2 = new User();
        hevm.store(
            address(usdc),
            keccak256(abi.encode(address(user2), uint256(9))),
            bytes32(uint256(200000000000))
        );
        user2.approve(address(usdc), address(elf));

        user3 = new User();
        hevm.store(
            address(usdc),
            keccak256(abi.encode(address(user3), uint256(9))),
            bytes32(uint256(600000000000))
        );
        user3.approve(address(usdc), address(elf));
    }

    /// @notice test deposit and withdraw integration test
    function test_depositAndWithdraw() public {
        assertTrue(elf.governance() == address(this));
        yusdcAsset.setPool(address(elf));

        // Test deposits
        user1.call_deposit(address(elf), 1e11);
        user2.call_deposit(address(elf), 2e11);
        user1.call_deposit(address(elf), 1e11);
        user3.call_deposit(address(elf), 6e11);

        uint256 pricePerFullShare = yusdc.getPricePerFullShare();
        uint256 balance = elf.balance() * pricePerFullShare / 1e18;
        assertTrue(balance + 5 >= 1e12); // add 5 cause of dusty trx

        /* At this point:
         *         deposited     held
         * User 1: 20,000 USDC | 0 USDC
         * user 2: 20,000 USDC | 0 USDC
         * User 3: 60,000 USDC | 0 USDC
         */

        // Test a transfer
        uint256 user1Bal = elf.balanceOf(address(user1));
        uint256 user3Bal = elf.balanceOf(address(user3));
        user3.call_transfer(address(elf), address(user1), user3Bal / 2);
        assertEq(
            elf.balanceOf(address(user1)) * elf.balanceOf(address(user3)),
            user1Bal + user3Bal
        );

        /* At this point:
         *         deposited     held
         * User 1: 50,000 USDC | 0 USDC
         * user 2: 20,000 USDC | 0 USDC
         * User 3: 30,000 USDC | 0 USDC
         */

        // Test withdraws
        uint256 toWithdraw = 1000000;
        user1Bal = elf.balanceOf(address(user1));
        pricePerFullShare = yusdc.getPricePerFullShare();
        uint256 balanceUSDC = user1Bal * pricePerFullShare / 1e18;
        uint256 withdrawUSDC = toWithdraw * pricePerFullShare / 1e18;

        user1.call_withdraw(address(elf), toWithdraw);
        assertEq(elf.balanceOf(address(user1)), user1Bal - toWithdraw);
        assertEq(usdc.balanceOf(address(user1)), withdrawUSDC);

        /* At this point:
         *         deposited     held
         * User 1: 49,999 USDC | 1 USDC
         * user 2: 20,000 USDC | 0 USDC
         * User 3: 30,000 USDC | 0 USDC
         */

        user1.call_withdraw(address(elf), elf.balanceOf(address(user1)));
        assertEq(elf.balanceOf(address(user1)), 0);

        user2.call_withdraw(address(elf), elf.balanceOf(address(user2)));
        assertEq(elf.balanceOf(address(user2)), 0);

        user3.call_withdraw(address(elf), elf.balanceOf(address(user3)));
        assertEq(elf.balanceOf(address(user3)), 0);

        /* At this point:
         *         deposited     held
         * User 1: 0 USDC      | 50,000 USDC
         * user 2: 0 USDC      | 20,000 USDC
         * User 3: 0 USDC      | 30,000 USDC
         */

        uint256 totalUSDC = usdc.balanceOf(address(user1)) + usdc.balanceOf(address(user2)) + usdc.balanceOf(address(user3));
        assertTrue(totalUSDC + 5 >= 1e12); //adding a bit for dusty trx
    }

    /// @notice test that we get the correct balance from elf pool
    function test_balance() public {
        assertTrue(elf.governance() == address(this));
        yusdcAsset.setPool(address(elf));

        user1.call_deposit(address(elf), 100000000000);

        uint256 pricePerFullShare = yusdc.getPricePerFullShare();
        uint256 balance = elf.balance() * pricePerFullShare / 1e18;

        assertTrue(balance >= 99999999999);
    }

    /// @notice test that we get the correct underlying balance from elf pool
    function test_balanceUnderlying() public {
        assertTrue(elf.governance() == address(this));
        yusdcAsset.setPool(address(elf));

        user1.call_deposit(address(elf), 100000000000);

        assertTrue(elf.balanceUnderlying() >= 99999999999);
    }
}
