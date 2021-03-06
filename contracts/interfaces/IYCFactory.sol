// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../assets/YC.sol";

interface IYCFactory {
    function deployYc(
        address tranche,
        string memory elfSymbol,
        uint256 expiration,
        uint8 underlyingDecimals
    ) external returns (YC yc);
}
