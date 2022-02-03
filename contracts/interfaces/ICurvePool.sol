pragma solidity ^0.8.0;

interface ICurvePool {
    function remove_liquidity_one_coin(
        uint256 amount,
        uint256 idx,
        uint256 minAmount
    ) external;

    function remove_liquidity_one_coin(
        uint256 amount,
        int128 idx,
        uint256 minAmount
    ) external;
}
