// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface I3CurvePoolDepositZap {
    function add_liquidity(
        address metapool,
        uint256[4] memory amountCtx,
        uint256 minAmount
    ) external payable;
}
