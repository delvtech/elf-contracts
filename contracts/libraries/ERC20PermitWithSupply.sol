// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./ERC20Permit.sol";

abstract contract ERC20PermitWithSupply is ERC20Permit {
    uint256 public totalSupply;

    function _mint(address account, uint256 amount) internal override {
        balanceOf[account] = balanceOf[account] + amount;
        totalSupply += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal override {
        balanceOf[account] = balanceOf[account] - amount;
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }
}
