// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.7;

interface IConvergentCurvePool {
    function underlying() external view returns (address);

    function bond() external view returns (address);

    function blockTimestampLast() external returns (uint256);

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
}
