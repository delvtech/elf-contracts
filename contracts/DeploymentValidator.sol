// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./libraries/Authorizable.sol";
import "./interfaces/IDeploymentValidator.sol";

contract DeploymentValidator is IDeploymentValidator, Authorizable {
    mapping(address => bool) public wrappedPositions;
    mapping(address => bool) public pools;
    mapping(bytes32 => bool) public pairs;

    constructor(address _owner) {
        _authorize(_owner);
    }

    function validateWPAddress(address wrappedPosition)
        external
        override
        onlyAuthorized
    {
        wrappedPositions[wrappedPosition] = true;
    }

    function validatePoolAddress(address pool)
        external
        override
        onlyAuthorized
    {
        pools[pool] = true;
    }

    function validateAddresses(address wrappedPosition, address pool)
        external
        override
        onlyAuthorized
    {
        bytes32 data = keccak256(abi.encodePacked(wrappedPosition, pool));
        pairs[data] = true;
    }

    function checkWPValidation(address wrappedPosition)
        external
        view
        override
        returns (bool)
    {
        return wrappedPositions[wrappedPosition];
    }

    function checkPoolValidation(address pool)
        external
        view
        override
        returns (bool)
    {
        return pools[pool];
    }

    function checkPairValidation(address wrappedPosition, address pool)
        external
        view
        override
        returns (bool)
    {
        bytes32 data = keccak256(abi.encodePacked(wrappedPosition, pool));
        return pairs[data];
    }
}
