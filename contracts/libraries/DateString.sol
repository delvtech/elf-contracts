// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library DateString {
    uint256 public constant SECONDS_PER_DAY = 24 * 60 * 60;
    uint256 public constant SECONDS_PER_HOUR = 60 * 60;
    uint256 public constant SECONDS_PER_MINUTE = 60;
    int256 public constant OFFSET19700101 = 2440588;

    // This function was forked from https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary
    // ------------------------------------------------------------------------
    // Calculate year/month/day from the number of days since 1970/01/01 using
    // the date conversion algorithm from
    //   http://aa.usno.navy.mil/faq/docs/JD_Formula.php
    // and adding the offset 2440588 so that 1970/01/01 is day 0
    //
    // int L = days + 68569 + offset
    // int N = 4 * L / 146097
    // L = L - (146097 * N + 3) / 4
    // year = 4000 * (L + 1) / 1461001
    // L = L - 1461 * year / 4 + 31
    // month = 80 * L / 2447
    // dd = L - 2447 * month / 80
    // L = month / 11
    // month = month + 2 - 12 * L
    // year = 100 * (N - 49) + year + L
    // ------------------------------------------------------------------------
    // solhint-disable-next-line private-vars-leading-underscore
    function _daysToDate(uint256 _days)
        internal
        pure
        returns (
            uint256 year,
            uint256 month,
            uint256 day
        )
    {
        int256 __days = int256(_days);
        // solhint-disable-next-line var-name-mixedcase
        int256 L = __days + 68569 + OFFSET19700101;
        // solhint-disable-next-line var-name-mixedcase
        int256 N = (4 * L) / 146097;
        L = L - (146097 * N + 3) / 4;
        int256 _year = (4000 * (L + 1)) / 1461001;
        L = L - (1461 * _year) / 4 + 31;
        int256 _month = (80 * L) / 2447;
        int256 _day = L - (2447 * _month) / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint256(_year);
        month = uint256(_month);
        day = uint256(_day);
    }

    /// @dev Writes a prefix and an timestamp encoding to an output storage location
    ///      This function is designed to only work with ASCII encoded strings. No emojis please.
    /// @param _prefix The string to write before the timestamp
    /// @param _timestamp the timestamp to encode and store
    /// @param _output the storage location of the output string
    /// NOTE - Current cost ~90k if gas is problem revisit and use assembly to remove the extra
    ///        sstore s.
    function encodeAndWriteTimestamp(
        string memory _prefix,
        uint256 _timestamp,
        string storage _output
    ) internal {
        // Cast the prefix string to a byte array
        bytes memory bytePrefix = bytes(_prefix);
        // Cast the output string to a byte array
        bytes storage bytesOutput = bytes(_output);
        // Copy the bytes from the prefix onto the byte array
        // NOTE - IF PREFIX CONTAINS NON-ASCII CHARS THIS WILL CAUSE AN INCORRECT STRING LENGTH
        for (uint256 i = 0; i < bytePrefix.length; i++) {
            bytesOutput.push(bytePrefix[i]);
        }
        // Add a ':' to the string to separate the prefix from the the date
        bytesOutput.push(bytes1(":"));
        // Add the date string
        timestampToDateString(_timestamp, _output);
    }

    /// @dev Converts a unix second encoded timestamp to a date format (year, month, day)
    ///      then writes the string encoding of that to the output pointer.
    /// @param _timestamp the unix seconds timestamp
    /// @param _outputPointer the storage pointer to change.
    function timestampToDateString(
        uint256 _timestamp,
        string storage _outputPointer
    ) internal {
        // We pretend the string is a 'bytes' only push UTF8 encodings to it
        bytes storage output = bytes(_outputPointer);
        // First we get the day month and year
        (uint256 year, uint256 month, uint256 day) = _daysToDate(
            _timestamp / SECONDS_PER_DAY
        );
        // First we add encoded day to the string
        {
            // Round out the second digit
            uint256 firstDigit = day / 10;
            // add it to the encoded byte for '0'
            output.push(bytes1(uint8(bytes1("0")) + uint8(firstDigit)));
            // Extract the second digit
            uint256 secondDigit = day % 10;
            // add it to the string
            output.push(bytes1(uint8(bytes1("0")) + uint8(secondDigit)));
        }
        output.push(bytes1("-"));
        // Next we encode the month string and add it
        if (month == 1) {
            output.push(bytes1("J"));
            output.push(bytes1("A"));
            output.push(bytes1("N"));
        } else if (month == 2) {
            output.push(bytes1("F"));
            output.push(bytes1("E"));
            output.push(bytes1("B"));
        } else if (month == 3) {
            output.push(bytes1("M"));
            output.push(bytes1("A"));
            output.push(bytes1("R"));
        } else if (month == 4) {
            output.push(bytes1("A"));
            output.push(bytes1("P"));
            output.push(bytes1("R"));
        } else if (month == 5) {
            output.push(bytes1("M"));
            output.push(bytes1("A"));
            output.push(bytes1("Y"));
        } else if (month == 6) {
            output.push(bytes1("J"));
            output.push(bytes1("U"));
            output.push(bytes1("N"));
        } else if (month == 7) {
            output.push(bytes1("J"));
            output.push(bytes1("U"));
            output.push(bytes1("L"));
        } else if (month == 8) {
            output.push(bytes1("A"));
            output.push(bytes1("U"));
            output.push(bytes1("G"));
        } else if (month == 9) {
            output.push(bytes1("S"));
            output.push(bytes1("E"));
            output.push(bytes1("P"));
        } else if (month == 10) {
            output.push(bytes1("O"));
            output.push(bytes1("C"));
            output.push(bytes1("T"));
        } else if (month == 11) {
            output.push(bytes1("N"));
            output.push(bytes1("O"));
            output.push(bytes1("V"));
        } else if (month == 12) {
            output.push(bytes1("D"));
            output.push(bytes1("E"));
            output.push(bytes1("C"));
        } else {
            revert("date decoding error");
        }
        output.push(bytes1("-"));
        // We take the last two digits of the year
        // Hopefully that's enough
        {
            uint256 lastDigits = year % 100;
            // Round out the second digit
            uint256 firstDigit = lastDigits / 10;
            // add it to the encoded byte for '0'
            output.push(bytes1(uint8(bytes1("0")) + uint8(firstDigit)));
            // Extract the second digit
            uint256 secondDigit = lastDigits % 10;
            // add it to the string
            output.push(bytes1(uint8(bytes1("0")) + uint8(secondDigit)));
        }
    }
}
