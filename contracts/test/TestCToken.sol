// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/external/CTokenInterfaces.sol";

abstract contract TestCToken is CErc20Interface {
    // returns a nonzero integer to test cases when Compound's mint fails
    function mint(uint256 mintAmount) external override pure returns (uint256) {
        return 1;
    }

    // returns a nonzero integer to test cases when Compound's redeem fails
    function redeem(uint256 redeemTokens)
        external
        override
        pure
        returns (uint256)
    {
        return 1;
    }
}
