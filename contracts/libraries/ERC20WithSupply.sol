// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";

abstract contract ERC20WithSupply is ERC20 {
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
