// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./libraries/Authorizable.sol";

contract VaultWrapperRegistry is Authorizable {
    struct VaultWrapperPair {
        address vault;
        address wrapper;
    }

    VaultWrapperPair[] public pairs;

    /// @notice Constructs this contract and stores needed data
    /// @param _owner The contract owner authorized to validate addresses
    constructor(address _owner) {
        // authorize the owner address to be able to execute the validations
        _authorize(_owner);
    }

    /// @notice adds a vault + wrapper pair of addresses to state array
    /// @param vault the vault contract address
    /// @param wrapper the wrapped position contract address
    function validatePairs(address vault, address wrapper)
        external
        onlyAuthorized
    {
        pairs.push(VaultWrapperPair(vault, wrapper));
    }

    /// @notice shows the entire array of vault/wrapper pairs
    /// @return the entire array of struct pairs
    function viewRegistry() external view returns (VaultWrapperPair[] memory) {
        return pairs;
    }
}
