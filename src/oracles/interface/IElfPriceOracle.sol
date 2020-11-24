// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.8 <0.8.0;

interface IElfPriceOracle {
    function getPrice(address fromToken, address toToken)
        external
        view
        returns (uint256);
}
