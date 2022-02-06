// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface IConvergentCurvePool {
    function totalSupply() external view returns (uint256);

    function solveTradeInvariant(
        uint256 amountX,
        uint256 reserveX,
        uint256 reserveY,
        bool out
    ) external view returns (uint256);
}
