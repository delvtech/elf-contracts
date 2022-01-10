// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.7;

import { IConvergentCurvePool } from "../interfaces/IConvergentCurvePool.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

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

contract SimpleOracle {
    uint256 public immutable period; // Frequency at which avg get calculated for the cumulative balance ratio.
    address public immutable bond; // Address of the principal token i.e used as the bond token in the given convergent curve pool.
    address public immutable underlying; // Address of the liquidity token.
    IConvergentCurvePool public immutable pool; // Address of the pool (supports balancer v2).

    uint256 public blockTimestampLast; // Last timestamp at which avg cumulative balance ratio get updated.
    uint256 public cumulativeBalancesRatioLast; // Last cumulativeBalancesRatio value.
    uint256 public avgCumulativeBalancesRatio; // Avg of cumulative balance ratio.

    error PeriodIsLessThanThreshold(uint256 period);
    error NoReserveExists();
    error PeriodNotElapsed();
    error InvalidToken();

    constructor(uint256 _period, address _pool) {
        if (_period < 30 minutes) {
            revert PeriodIsLessThanThreshold(_period);
        }
        IConvergentCurvePool __pool = IConvergentCurvePool(_pool);

        pool = __pool;
        bond = __pool.bond();
        underlying = __pool.underlying();
        period = _period;

        (, uint256[] memory balances, ) = IVaultLike(__pool.getVault())
            .getPoolTokens(__pool.getPoolId());
        if (!(balances[0] != uint256(0) && balances[1] != uint256(0))) {
            revert NoReserveExists();
        }
        blockTimestampLast = __pool.blockTimestampLast();
    }

    function update() external {
        (uint256 cumulativeBalancesRatio, uint256 blockTimestamp) = pool
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
            amountOut = (amountIn * amountIn) / 1e18;
        }
    }
}
