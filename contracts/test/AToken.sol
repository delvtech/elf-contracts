// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";

import "../libraries/ERC20.sol";

contract AToken is ERC20 {
    constructor(address sender) ERC20("a token", "TOKEN") {
        mint(sender, 1e39);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
