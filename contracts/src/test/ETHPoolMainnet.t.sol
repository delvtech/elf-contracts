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
/// @title Elf Contract Mainnet Test for yETH
contract ElfContractsTestyWETH is DSTest {
    Hevm public hevm;
    IWETH public weth;

    User public user1;
    User public user2;
    User public user3;

    YearnVault public yweth;
    YVaultAssetProxy public ywethAsset;

    ElfFactory public factory;
    Elf public elf;

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        factory = new ElfFactory();

        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        yweth = YearnVault(0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7);

        ywethAsset = new YVaultAssetProxy(address(yweth), address(weth));

        elf = factory.newPool(address(weth), address(ywethAsset));

        // create 3 users and provide funds through HEVM store
        user1 = new User();
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user1), uint256(3))),
            bytes32(uint256(20000 ether))
        );
        user1.approve(address(weth), address(elf));

        user2 = new User();
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user2), uint256(3))),
            bytes32(uint256(20000 ether))
        );
        user2.approve(address(weth), address(elf));

        user3 = new User();
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user3), uint256(3))),
            bytes32(uint256(60000 ether))
        );
        user3.approve(address(weth), address(elf));
    }

    /// @notice test deposit and withdraw integration test
    function test_depositAndWithdraw() public {
        assertTrue(elf.governance() == address(this));
        ywethAsset.setPool(address(elf));

        // Test deposits
        user1.call_deposit(address(elf), 10000 ether);
        user2.call_deposit(address(elf), 20000 ether);
        user1.call_deposit(address(elf), 10000 ether);
        user3.call_deposit(address(elf), 60000 ether);

        uint256 pricePerFullShare = yweth.getPricePerFullShare();
        uint256 balance = (elf.balance() * pricePerFullShare) / 1e18;
        assertTrue(balance + 5 >= 1e12); // add 5 cause of dusty trx

        /* At this point:
         *         deposited     held
         * User 1: 20,000 weth | 0 weth
         * user 2: 20,000 weth | 0 weth
         * User 3: 60,000 weth | 0 weth
         */

        // Test a transfer
        uint256 user1Bal = elf.balanceOf(address(user1));
        uint256 user3Bal = elf.balanceOf(address(user3));
        user3.call_transfer(address(elf), address(user1), user3Bal / 2);
        assertEq(
            elf.balanceOf(address(user1)) + elf.balanceOf(address(user3)),
            user1Bal + user3Bal
        );

        /* At this point:
         *         deposited     held
         * User 1: 50,000 weth | 0 weth
         * user 2: 20,000 weth | 0 weth
         * User 3: 30,000 weth | 0 weth
         */

        // Test withdraws
        uint256 toWithdraw = 1 ether;
        user1Bal = elf.balanceOf(address(user1));
        pricePerFullShare = yweth.getPricePerFullShare();
        uint256 balanceweth = (user1Bal * pricePerFullShare) / 1e18;
        uint256 withdrawweth = (toWithdraw * pricePerFullShare) / 1e18;

        user1.call_withdraw(address(elf), toWithdraw);
        assertEq(elf.balanceOf(address(user1)), user1Bal - toWithdraw);
        assertEq(weth.balanceOf(address(user1)), withdrawweth);

        /* At this point:
         *         deposited     held
         * User 1: 49,999 weth | 1 weth
         * user 2: 20,000 weth | 0 weth
         * User 3: 30,000 weth | 0 weth
         */

        user1.call_withdraw(address(elf), elf.balanceOf(address(user1)));
        assertEq(elf.balanceOf(address(user1)), 0);

        user2.call_withdraw(address(elf), elf.balanceOf(address(user2)));
        assertEq(elf.balanceOf(address(user2)), 0);

        user3.call_withdraw(address(elf), elf.balanceOf(address(user3)));
        assertEq(elf.balanceOf(address(user3)), 0);

        /* At this point:
         *         deposited     held
         * User 1: 0 weth      | 50,000 weth
         * user 2: 0 weth      | 20,000 weth
         * User 3: 0 weth      | 30,000 weth
         */

        uint256 totalweth = weth.balanceOf(address(user1)) +
            weth.balanceOf(address(user2)) +
            weth.balanceOf(address(user3));
        assertTrue(totalweth + 5 >= 100000 ether); //adding a bit for dusty trx
    }

    /// @notice test that we get the correct balance from elf pool
    function test_balance() public {
        assertTrue(elf.governance() == address(this));
        ywethAsset.setPool(address(elf));

        user1.call_deposit(address(elf), 10000 ether);

        uint256 pricePerFullShare = yweth.getPricePerFullShare();
        uint256 balance = (elf.balance() * pricePerFullShare) / 1e18;

        // Sub 1 ETH for 0.01% loss due to high volume deposit
        assertTrue(balance >= 10000 ether - 1 ether);
    }

    /// @notice test that we get the correct underlying balance from elf pool
    function test_balanceUnderlying() public {
        assertTrue(elf.governance() == address(this));
        ywethAsset.setPool(address(elf));

        user1.call_deposit(address(elf), 10000 ether);

        // Sub 1 ETH for 0.01% loss due to high volume deposit
        assertTrue(elf.balanceUnderlying() >= 10000 ether - 1 ether);
    }
}
