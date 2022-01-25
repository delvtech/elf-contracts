// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

import { IERC20 } from "../interfaces/IERC20.sol";

contract TestTranche {
    IERC20 private _baseToken;
    uint256 private _timestamp;

    constructor(address baseToken, uint256 timestamp) {
        _baseToken = IERC20(baseToken);
        _timestamp = timestamp;
    }

    function underlying() external view returns (IERC20) {
        return _baseToken;
    }

    function unlockTimestamp() external view returns (uint256) {
        return _timestamp;
    }
}
