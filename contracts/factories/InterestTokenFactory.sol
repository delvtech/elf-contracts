// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../InterestToken.sol";
import "../interfaces/IERC20.sol";

contract InterestTokenFactory {
    /// @dev Emitted when a new InterestToken is created.
    /// @param token the token address
    /// @param tranche the tranche address
    event InterestTokenCreated(address indexed token, address indexed tranche);

    /// @notice Deploy a new interest token contract
    /// @param _tranche The Tranche contract associated with this interest token.
    /// The Tranche contract is also the mint authority.
    /// @param _strategySymbol The symbol of the associated Wrapped Position contract.
    /// @param _expiration Expiration timestamp of the Tranche contract.
    /// @param _underlyingDecimals The number of decimal places the underlying token adheres to.
    /// @return The deployed interest token contract
    function deployInterestToken(
        address _tranche,
        string memory _strategySymbol,
        uint256 _expiration,
        uint8 _underlyingDecimals
    ) public returns (InterestToken) {
        InterestToken token = new InterestToken(
            _tranche,
            _strategySymbol,
            _expiration,
            _underlyingDecimals
        );

        emit InterestTokenCreated(address(token), _tranche);

        return token;
    }
}
