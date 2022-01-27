// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.7;

interface IConvergentCurvePool {
    function underlying() external view returns (address);

    function bond() external view returns (address);

    /// @notice Returns required matrix to help oracles for deriving prices.
    /// @return uint256 Timestamp at which balances of assets get updated last.
    /// @return uint256 Cumulative balance ratio.
    function getCurrentCumulativeRatio()
        external
        view
        returns (uint256, uint256);

    /// @dev Returns the vault for this pool
    /// @return The vault for this pool
    function getVault() external view returns (address);

    /// @dev Returns the poolId for this pool
    /// @return The poolId for this pool
    function getPoolId() external view returns (bytes32);

    ///@notice Update the cumulative ratio and calculates the avg cumulative ratio for a given period.
    function update() external;

    /// @notice Synchronize the bond and underlying balance and calculate the `_cumulativeBalancesRatio`.
    function sync() external;

    /// @notice Get the amount of out token user receive corresponds to `amountIn`.
    /// @param  token Address of the token that is treated as the base token for the price.
    /// @param  amountIn Amount of the token corresponds to `amountOut` get calculated.
    /// @return amountOut Amount of token B user will get corresponds to given amountIn.
    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);
}
