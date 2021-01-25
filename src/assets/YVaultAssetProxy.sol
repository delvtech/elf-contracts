// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVaultV1.sol";
import "../interfaces/IBPool.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

/// @author Element Finance
/// @title Yearn Vault v1 Asset Proxy
contract YVaultAssetProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;
    YearnVault public vault;

    address public pool;
    address public governance;

    constructor(address _vault, address _token) public {
        governance = msg.sender;
        pool = msg.sender;
        vault = YearnVault(_vault);
        token = IERC20(_token);
        token.approve(_vault, uint256(-1));
    }

    /// @notice let governance update itself
    /// @param _governance new governance address
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    /// @notice let governance update the pool address
    /// @param _pool the new pool address
    function setPool(address _pool) external {
        require(msg.sender == governance, "!governance");
        pool = _pool;
    }

    /// @notice deposit the balace of underlying tokens to the vault
    function deposit() external {
        require(msg.sender == pool, "!pool");

        vault.deposit(token.balanceOf(address(this)));
        vault.transfer(pool, vault.balanceOf(address(this)));
    }

    /// @notice withdraw the balance of vault shares held by the proxy
    function withdraw() external {
        require(msg.sender == pool, "!pool");

        vault.withdraw(vault.balanceOf(address(this)));
        token.safeTransfer(pool, token.balanceOf(address(this)));
    }

    /// @notice get the underlying amount of tokens per shares given
    /// @param _amount the amount of shares you want to know the value of
    /// @return value of shares in underlying token
    function underlying(uint256 _amount) external view returns (uint256) {
        return vault.getPricePerFullShare().mul(_amount).div(1e18);
    }

    /// @notice Function to reset approvals for the proxy
    function approve() external {
        token.approve(address(vault), 0);
        token.approve(address(vault), uint256(-1));
    }
}
