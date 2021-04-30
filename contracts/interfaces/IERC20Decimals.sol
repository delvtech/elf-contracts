// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.7.0;

import "../balancer-core-v2/lib/openzeppelin/ERC20.sol";

interface IERC20Decimals is IERC20 {
    // Non standard but almost all erc20 have this
    function decimals() external view returns (uint8);
}
