// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./libraries/Authorizable.sol";

contract WrapperRegistry is Authorizable {
    address[] public wrappers;

    /// @notice Constructs this contract and stores needed data
    /// @param _owner The contract owner authorized to validate addresses
    constructor(address _owner) {
        // authorize the owner address to be able to execute the validations
        _authorize(_owner);
    }

    /// @notice adds a vault + wrapper pair of addresses to state array
    /// @param wrapper the wrapped position contract address
    function registerWrapper(address wrapper) external onlyAuthorized {
        wrappers.push(wrapper);
    }

    /// @notice shows the entire array of vault/wrapper pairs
    /// @return the entire array of struct pairs
    function viewRegistry() external view returns (address[] memory) {
        return wrappers;
    }
}
