// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface IDeploymentValidator {
    function validateWPAddress(address wrappedPosition) external;

    function validatePoolAddress(address pool) external;

    function validateAddresses(address wrappedPosition, address pool) external;

    function checkWPValidation(address wrappedPosition) external returns (bool);

    function checkPoolValidation(address pool) external returns (bool);

    function checkPairValidation(address wrappedPosition, address pool)
        external
        returns (bool);
}
