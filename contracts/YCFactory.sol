// SPDX-License-Identifier: Apache-2.0

import "./Tranche.sol";
import "./assets/YC.sol";
import "./interfaces/IElf.sol";
import "./interfaces/IERC20.sol";

pragma solidity ^0.8.0;

contract YCFactory {
    function deployYc(
        address tranche,
        string memory elfSymbol,
        uint256 expiration,
        uint8 localUnderlyingDecimals
    ) public returns (YC yc) {
        return new YC(tranche, elfSymbol, expiration, localUnderlyingDecimals);
    }
}