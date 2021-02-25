// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVaultV2.sol";
import "../interfaces/IBPool.sol";
import "../Elf.sol";

import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "hardhat/console.sol";

/// @author Element Finance
/// @title Yearn Vault v1 Asset Proxy
contract YVaultAssetProxy is Elf {
    using SafeERC20 for IERC20;
    using Address for address;

    YearnVault public immutable vault;
    uint8 public immutable vaultDecimals;

    constructor(
        address _vault,
        address _token,
        string memory _name,
        string memory _symbol
    ) Elf(_token, _name, _symbol) {
        vault = YearnVault(_vault);
        token.approve(_vault, type(uint256).max);
        vaultDecimals = IERC20(_vault).decimals();
    }

    /// @dev Makes the actual deposit into the yearn vault
    /// @return (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        // Load the balance of this contract
        uint256 amount = token.balanceOf(address(this));
        // Deposit into the vault
        // uint256 gasBefore = gasleft();
        // Deposit and get the shares that were minted to this
        uint256 shares = vault.deposit(amount, address(this));
        // console.log("yearn gas used", gasBefore - gasleft());
        // As of V2 yearn vault shares are the same decimals as the
        // underlying. But we want our tokens to have a consistent
        return (shares, amount);
    }

    /// @notice withdraw the balance of vault shares held by the proxy
    /// @param shares the number of shares to withdraw
    /// @param _destination the address to send the output funds
    function _withdraw(uint256 shares, address _destination)
        internal
        override
        returns (uint256)
    {
        // Withdraws shares from the vault with max loss 0.01%
        uint256 amountReceived = vault.withdraw(shares, _destination, 1);
        return amountReceived;
    }

    /// @notice get the underlying amount of tokens per shares given
    /// @param _amount the amount of shares you want to know the value of
    /// @return value of shares in underlying token
    function _underlying(uint256 _amount)
        internal
        override
        view
        returns (uint256)
    {
        // uint256 gasBefore = gasleft();
        uint256 pricePerShare = vault.pricePerShare();
        // console.log("Yearn pps call cost", gasBefore- gasleft());
        return (pricePerShare * _amount) / (10**vaultDecimals);
    }

    function _vault() internal override view returns (IERC20) {
        return IERC20(address(vault));
    }

    /// @notice Function to reset approvals for the proxy
    function approve() external {
        token.approve(address(vault), 0);
        token.approve(address(vault), type(uint256).max);
    }
}
