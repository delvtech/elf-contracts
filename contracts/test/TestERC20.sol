// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../libraries/ERC20.sol";

// An ERC20 with specified decimals, we may add unlimited mint and other test functions
contract TestERC20 is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _setupDecimals(decimals_);
    }
}
