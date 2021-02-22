// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVaultV1.sol";
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

    YearnVault public vault;
    address public governance;

    constructor(address vault_, address _token, string memory _name, string memory _symbol)
    Elf(_token, _name, _symbol) {
        governance = msg.sender;
        vault = YearnVault(vault_);
        token.approve(vault_, type(uint256).max);
    }

    /// @notice let governance update itself
    /// @param _governance new governance address
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    /// @dev Makes the actual deposit into the yearn vault
    /// @return (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        // Load the balance of this contract
        uint256 amount = token.balanceOf(address(this));
        // Deposit into the vault
        uint256 gasBefore = gasleft();
        uint256 shares = vault.deposit(amount);
        console.log("yearn gas used", gasBefore - gasleft());
        return (shares, amount);
    }

    /// @notice withdraw the balance of vault shares held by the proxy
    function _withdraw(uint256 shares) internal override returns(uint256) {
        // Withdraws shares from the vault
        uint256 amountReceived = vault.withdraw(shares);
        return amountReceived;
    }

    /// @notice get the underlying amount of tokens per shares given
    /// @param _amount the amount of shares you want to know the value of
    /// @return value of shares in underlying token
    function _underlying(uint256 _amount) internal view override returns (uint256) {
        return (vault.getPricePerFullShare() * _amount) / 1e18;
    }

    function _vault() internal view override returns(IERC20) {
        return IERC20(address(vault));
    }

    /// @notice Function to reset approvals for the proxy
    function approve() external {
        token.approve(address(vault), 0);
        token.approve(address(vault), type(uint256).max);
    }
}
