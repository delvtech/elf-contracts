// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./libraries/Authorizable.sol";

contract VaultWrapperRegistry is Authorizable {
    // a mapping of wrapped positions deployed by Element
    mapping(address => bool) public wrappedPositions;
    // a mapping of Yearn vault contracts
    mapping(address => bool) public vaults;
    // a mapping of wrapped position + vault pairs that are used by Element
    // we keccak256 hash these tuples together to serve as the mapping keys
    mapping(bytes32 => bool) public pairs;

    /// @notice Constructs this contract and stores needed data
    /// @param _owner The contract owner authorized to validate addresses
    constructor(address _owner) {
        // authorize the owner address to be able to execute the validations
        _authorize(_owner);
    }

    /// @notice adds a wrapped position address to the mapping
    /// @param wrappedPosition The wrapped position contract address
    function validateWPAddress(address wrappedPosition) public onlyAuthorized {
        // add address to mapping to indicating it was deployed by Element
        wrappedPositions[wrappedPosition] = true;
    }

    /// @notice adds a vault address to the mapping
    /// @param vault the vault contract address
    function validateVaultAddress(address vault) public onlyAuthorized {
        // add address to mapping to indicating it was deployed by Element
        vaults[vault] = true;
    }

    /// @notice adds a wrapped position + vault pair of addresses to mapping
    /// @param wrappedPosition the wrapped position contract address
    /// @param vault the vault contract address
    function validateAddresses(address wrappedPosition, address vault)
        external
        onlyAuthorized
    {
        // add to vault validation mapping
        validateVaultAddress(vault);
        // add to wp validation mapping
        validateWPAddress(wrappedPosition);
        // hash together the contract addresses
        bytes32 data = keccak256(abi.encodePacked(wrappedPosition, vault));
        // add the hashed pair into the mapping
        pairs[data] = true;
    }

    /// @notice checks to see if the address has been validated
    /// @param wrappedPosition the address to check
    /// @return true if validated, false if not
    function checkWPValidation(address wrappedPosition)
        external
        view
        returns (bool)
    {
        return wrappedPositions[wrappedPosition];
    }

    /// @notice checks to see if the address has been validated
    /// @param vault the address to check
    /// @return true if validated, false if not
    function checkVaultValidation(address vault) external view returns (bool) {
        return vaults[vault];
    }

    /// @notice checks to see if the pair of addresses have been validated
    /// @param wrappedPosition the wrapped position address to check
    /// @param vault the vault address to check
    /// @return true if validated, false if not
    function checkPairValidation(address wrappedPosition, address vault)
        external
        view
        returns (bool)
    {
        bytes32 data = keccak256(abi.encodePacked(wrappedPosition, vault));
        return pairs[data];
    }
}
