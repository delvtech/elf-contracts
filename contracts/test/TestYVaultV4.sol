// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./TestYVault.sol";

// NOTE - the test y vault uses the formula of 0.4.2 and versions prior to
//        0.3.2, so when we test the YAssetProxyV4 we actually want the same logic
//        except that we want to return a diff version.
//        The subtly of 0.3.2 - 0.3.5 yearn vaults is tested in the mainnet tests.

contract TestYVaultV4 is TestYVault {
    constructor(address _token, uint8 _decimals)
        TestYVault(_token, _decimals)
    {}

    function apiVersion() external pure override returns (string memory) {
        return ("0.4.2");
    }
}
