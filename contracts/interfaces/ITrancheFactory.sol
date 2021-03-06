// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../assets/YC.sol";

interface ITrancheFactory {
    function getData()
        external
        returns (
            address,
            uint256,
            YC
        );
}
