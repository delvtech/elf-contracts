// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../libraries/DateString.sol";

contract TestDate {
    string public testString = "Tester";

    // This function will try encoding a timestamp and output-ing what happens
    function encodeTimestamp(uint256 timestamp)
        external
        returns (string memory)
    {
        // Will encode and store the result
        DateString._timestampToDateString(timestamp, testString);
        // We load and return the result
        return testString;
    }

    // This function allows access to encodeAndWriteTimestamp from DateString lib
    function encodePrefixTimestamp(string calldata prefix, uint256 timestamp)
        external
        returns (string memory)
    {
        // Will encode and store the result
        DateString._encodeAndWriteTimestamp(prefix, timestamp, testString);
        // We load and return the result
        return testString;
    }
}
