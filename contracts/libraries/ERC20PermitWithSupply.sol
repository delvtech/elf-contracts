// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./ERC20Permit.sol";

// This contract adds a total supply variable to the ERC20 lib to increase compatibility with standard
abstract contract ERC20PermitWithSupply is ERC20Permit {
    // The stored totalSupply, it equals all tokens minted - all tokens burned
    uint256 public totalSupply;

    /// @notice This function overrides the ERC20Permit Library's _mint and causes it
    ///          to track total supply.
    /// @param account the account to add tokens to
    /// @param amount the amount of tokens to add
    function _mint(address account, uint256 amount) internal override {
        // Increase account balance
        balanceOf[account] = balanceOf[account] + amount;
        // Increase total supply
        totalSupply += amount;
        // Emit a transfer from zero to emulate a mint
        emit Transfer(address(0), account, amount);
    }

    /// @notice This function overrides the ERC20Permit Library's _burn to decrement total supply
    /// @param account the account to burn from
    /// @param amount the amount of token to burn
    function _burn(address account, uint256 amount) internal override {
        // Decrease user balance
        balanceOf[account] = balanceOf[account] - amount;
        // Decrease total supply
        totalSupply -= amount;
        // Emit an event tracking the burn
        emit Transfer(account, address(0), amount);
    }
}
