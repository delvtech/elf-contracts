// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../libraries/DateString.sol";

contract DateTest {
    string public testString = "Tester";

    // This function will try encoding a timestamp and outputing what happens
    function encodeTimestamp(uint256 timestamp)
        external
        returns (string memory)
    {
        // Will encode and store the result
        DateString.timestampToDateString(timestamp, testString);
        // We load and return the result
        return testString;
    }

    // This function allows access to encodeAndWriteTimestamp from DateString lib
    function encodePrefixTimestamp(string calldata prefix, uint256 timestamp)
        external
        returns (string memory)
    {
        // Will encode and store the result
        DateString.encodeAndWriteTimestamp(prefix, timestamp, testString);
        // We load and return the result
        return testString;
    }
}
