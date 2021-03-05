// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../assets/YC.sol";

interface ITrancheFactory {
    function tempElfAddress() external view returns (address);

    function tempYC() external view returns (YC);

    function tempExpiration() external view returns (uint256);
}
