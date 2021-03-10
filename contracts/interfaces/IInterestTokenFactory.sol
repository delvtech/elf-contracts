// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../InterestToken.sol";

interface IInterestTokenFactory {
    function deployInterestToken(
        address tranche,
        string memory strategySymbol,
        uint256 expiration,
        uint8 underlyingDecimals
    ) external returns (InterestToken interestToken);
}
