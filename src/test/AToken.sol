// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";

import "../libraries/ERC20.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract AToken is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;

    constructor(address sender) public ERC20("a token", "TOKEN") {
        mint(sender, 1000000000000000000000000000000000000000);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
