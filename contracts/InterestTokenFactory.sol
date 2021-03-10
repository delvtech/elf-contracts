// SPDX-License-Identifier: Apache-2.0

import "./Tranche.sol";
import "./assets/InterestToken.sol";
import "./interfaces/IERC20.sol";

pragma solidity ^0.8.0;

contract InterestTokenFactory {
    /// @notice Deploy a new interest token contract
    /// @param tranche The Tranche contract associated with this interest token.
    /// The Tranche contract is also the mint authority.
    /// @param strategySymbol The symbol of the associated Wrapped Position contract.
    /// @param expiration Expiration timestamp of the Tranche contract.
    /// @param underlyingDecimals The number of decimal places the underlying token adheres to.
    /// @return The deployed interest token contract
    function deployInterestToken(
        address tranche,
        string memory strategySymbol,
        uint256 expiration,
        uint8 underlyingDecimals
    ) public returns (InterestToken) {
        return
            new InterestToken(
                tranche,
                strategySymbol,
                expiration,
                underlyingDecimals
            );
    }
}
