// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "../libraries/ERC20Permit.sol";

// An ERC20 with specified decimals, we may add unlimited mint and other test functions
contract TestERC20 is ERC20Permit {
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20Permit(name_, symbol_) {
        _setupDecimals(decimals_);
    }

    uint256 public totalSupply = 0;

    function setBalance(address destination, uint256 amount) external {
        balanceOf[destination] = amount;
        emit Transfer(address(0), destination, amount);
    }

    function uncheckedTransfer(address destination, uint256 amount) external {
        balanceOf[destination] += amount;
        emit Transfer(address(0), destination, amount);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
        totalSupply += amount;
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
        totalSupply -= amount;
    }
}
