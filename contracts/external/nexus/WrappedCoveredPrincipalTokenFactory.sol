// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

import { WrappedCoveredPrincipalToken, Authorizable, EnumerableSet } from "./WrappedCoveredPrincipalToken.sol";

/// @author Element Finance
/// @title WrappedCoveredPrincipalTokenFactory
contract WrappedCoveredPrincipalTokenFactory is Authorizable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Enumerable list of wrapped tokens that get created from the factory.
    EnumerableSet.AddressSet private _WrappedCoveredPrincipalTokens;

    // Emitted when new wrapped principal token get created.
    event WrappedCoveredPrincipalTokenCreated(
        address indexed _baseToken,
        address indexed _owner
    );

    /// @notice Initializing the owner of the contract.
    constructor(address owner_) {
        _authorize(owner_);
        setOwner(owner_);
    }

    /// @notice Allow the owner to create the new wrapped token.
    /// @param  _baseToken Address of the base token / underlying token that is used to buy the wrapped positions.
    /// @param  _owner Address of the owner of wrapped futures.
    /// @return address of wrapped futures token.
    function create(address _baseToken, address _owner)
        external
        onlyOwner
        returns (address)
    {
        // Validate the given params
        _zeroAddressCheck(_owner);
        _zeroAddressCheck(_baseToken);
        address wcPrincipal = address(
            new WrappedCoveredPrincipalToken(_baseToken, _owner)
        );
        _WrappedCoveredPrincipalTokens.add(wcPrincipal);
        emit WrappedCoveredPrincipalTokenCreated(_baseToken, _owner);
        return wcPrincipal;
    }

    /// @notice Returns the list of wrapped tokens that are whitelisted with the contract.
    ///         Order is not maintained.
    /// @return Array of addresses.
    function allWrappedCoveredPrincipalTokens()
        public
        view
        returns (address[] memory)
    {
        return _WrappedCoveredPrincipalTokens.values();
    }

    /// @notice Sanity check for the zero address check.
    function _zeroAddressCheck(address _target) internal pure {
        require(_target != address(0), "WFPF:ZERO_ADDRESS");
    }
}
