// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface ICurvePool {
    function add_liquidity(uint256[2] memory amountCtx, uint256 minAmount)
        external
        payable;

    function add_liquidity(uint256[3] memory amountCtx, uint256 minAmount)
        external
        payable;

    function remove_liquidity_one_coin(
        uint256 amountLp,
        uint256 idx,
        uint256 minAmount
    ) external payable;

    function remove_liquidity_one_coin(
        uint256 amount,
        int128 idx,
        uint256 minAmount
    ) external payable;

    function calc_token_amount(uint256[2] memory amounts, bool isDeposit)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[3] memory amounts, bool isDeposit)
        external
        view
        returns (uint256);

    function calc_withdraw_one_coin(uint256 amount, int128 selector)
        external
        view
        returns (uint256);

    function calc_withdraw_one_coin(uint256 amount, uint256 selector)
        external
        view
        returns (uint256);
}
