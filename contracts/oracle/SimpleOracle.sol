// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.7;

import { IConvergentCurvePool } from "../interfaces/IConvergentCurvePool.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/// Note -  Keeping this interface here to support 0.8.7 compiler as existing `IVault`interface
/// i.e https://github.com/balancer-labs/balancer-v2-monorepo/blob/master/pkg/vault/contracts/interfaces/IVault.sol doesn't
/// supports 0.8.7 compiler.
interface IVaultLike {
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            IERC20[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        );
}

/// @title Simple TWAR oracle based on the convergent curve pool.
/// @author Element Inc.
contract SimpleOracle {
    // Frequency at which avg get calculated for the cumulative balance ratio.
    uint256 public immutable period;
    // Address of the principal token i.e used as the bond token in the given convergent curve pool.
    address public immutable bond;
    // Address of the liquidity token.
    address public immutable underlying;
    // Address of the pool (supports balancer v2).
    IConvergentCurvePool public immutable pool;

    // Last timestamp at which avg cumulative balance ratio get updated.
    uint256 public blockTimestampLast;
    // Last cumulativeBalancesRatio value.
    uint256 public cumulativeBalancesRatioLast;
    // Avg of cumulative balance ratio.
    uint256 public avgCumulativeBalancesRatio;

    error PeriodIsLessThanThreshold(uint256 period);
    error NoReserveExists();
    error PeriodNotElapsed();
    error InvalidToken();

    ///@notice Constructor to initialize period and pool.
    constructor(uint256 _period, address _pool) {
        // Assuming more than 30 minutes time period is enough to counter the cost of
        // price manipulation attack by an attacker.
        // TBD - May need to change (Need a discussion within the team).
        if (_period < 30 minutes) {
            revert PeriodIsLessThanThreshold(_period);
        }
        IConvergentCurvePool __pool = IConvergentCurvePool(_pool);

        pool = __pool;
        bond = __pool.bond();
        underlying = __pool.underlying();
        period = _period;

        // Retrieve the vault balances related to the token existed in the given pool.
        // It is assumed that these balances are from past trade.
        (, uint256[] memory balances, ) = IVaultLike(__pool.getVault())
            .getPoolTokens(__pool.getPoolId());
        // Make sure that pool has reserve otherwise there is a no use of the oracle.
        if (!(balances[0] != uint256(0) && balances[1] != uint256(0))) {
            revert NoReserveExists();
        }
        // Set the timestamp at which pool balance were updated.
        (blockTimestampLast, ) = __pool.getCurrentCumulativeRatio();
    }

    ///@notice Update the cumulative ratio and calculates the avg cumulative ratio for a given period.
    function update() external {
        (uint256 blockTimestamp, uint256 cumulativeBalancesRatio) = pool
            .getCurrentCumulativeRatio();
        uint256 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed <= period) {
            revert PeriodNotElapsed();
        }
        avgCumulativeBalancesRatio =
            (cumulativeBalancesRatio - cumulativeBalancesRatioLast) /
            timeElapsed;
        cumulativeBalancesRatioLast = cumulativeBalancesRatio;
        blockTimestampLast = blockTimestamp;
    }

    /// @notice Get the amount of out token user receive corresponds to `amountIn`.
    /// @param  token Address of the token that is treated as the base token for the price.
    /// @param  amountIn Amount of the token corresponds to `amountOut` get calculated.
    /// @return amountOut Amount of token B user will get corresponds to given amountIn.
    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        if (token == bond) {
            amountOut = (amountIn * 1e18) / avgCumulativeBalancesRatio;
        } else {
            if (token != underlying) {
                revert InvalidToken();
            }
            amountOut = (amountIn * avgCumulativeBalancesRatio) / 1e18;
        }
    }
}
