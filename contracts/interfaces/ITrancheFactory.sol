// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../InterestToken.sol";
import "../libraries/DateString.sol";

interface ITrancheFactory {
    function getData()
        external
        returns (
            address,
            uint256,
            InterestToken,
            address
        );
}
