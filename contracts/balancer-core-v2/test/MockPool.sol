// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../lib/math/FixedPoint.sol";
import "../vault/interfaces/IVault.sol";
import "../vault/interfaces/IGeneralPool.sol";
import "../vault/interfaces/IMinimalSwapInfoPool.sol";

contract MockPool is IGeneralPool, IMinimalSwapInfoPool {
    using FixedPoint for uint256;

    IVault private immutable _vault;
    bytes32 private immutable _poolId;

    constructor(IVault vault, IVault.PoolSpecialization specialization) {
        _poolId = vault.registerPool(specialization);
        _vault = vault;
    }

    function getVault() external override view returns (IVault) {
        return _vault;
    }

    function getPoolId() external override view returns (bytes32) {
        return _poolId;
    }

    function registerTokens(
        IERC20[] memory tokens,
        address[] memory assetManagers
    ) external {
        _vault.registerTokens(_poolId, tokens, assetManagers);
    }

    function deregisterTokens(IERC20[] memory tokens) external {
        _vault.deregisterTokens(_poolId, tokens);
    }

    event OnJoinPoolCalled(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] currentBalances,
        uint256 latestBlockNumberUsed,
        uint256 protocolSwapFee,
        bytes userData
    );

    event OnExitPoolCalled(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] currentBalances,
        uint256 latestBlockNumberUsed,
        uint256 protocolSwapFee,
        bytes userData
    );

    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory currentBalances,
        uint256 latestBlockNumberUsed,
        uint256 protocolSwapFee,
        bytes memory userData
    )
        external
        override
        returns (
            uint256[] memory amountsIn,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        emit OnJoinPoolCalled(
            poolId,
            sender,
            recipient,
            currentBalances,
            latestBlockNumberUsed,
            protocolSwapFee,
            userData
        );

        (amountsIn, dueProtocolFeeAmounts) = abi.decode(
            userData,
            (uint256[], uint256[])
        );
    }

    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory currentBalances,
        uint256 latestBlockNumberUsed,
        uint256 protocolSwapFee,
        bytes memory userData
    )
        external
        override
        returns (
            uint256[] memory amountsOut,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        emit OnExitPoolCalled(
            poolId,
            sender,
            recipient,
            currentBalances,
            latestBlockNumberUsed,
            protocolSwapFee,
            userData
        );

        (amountsOut, dueProtocolFeeAmounts) = abi.decode(
            userData,
            (uint256[], uint256[])
        );
    }

    // Amounts in are multiplied by the multiplier, amounts out divided by it
    uint256 private _multiplier = FixedPoint.ONE;

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    // IGeneralPool
    function onSwapGivenIn(
        IPoolSwapStructs.SwapRequestGivenIn calldata swapRequest,
        uint256[] calldata,
        uint256,
        uint256
    ) external override view returns (uint256) {
        return swapRequest.amountIn.mul(_multiplier);
    }

    function onSwapGivenOut(
        IPoolSwapStructs.SwapRequestGivenOut calldata swapRequest,
        uint256[] calldata,
        uint256,
        uint256
    ) external override view returns (uint256) {
        uint256 amountIn = swapRequest.amountOut.div(_multiplier);
        return amountIn;
    }

    // IMinimalSwapInfoPool
    function onSwapGivenIn(
        IPoolSwapStructs.SwapRequestGivenIn calldata swapRequest,
        uint256,
        uint256
    ) external override view returns (uint256) {
        return swapRequest.amountIn.mul(_multiplier);
    }

    function onSwapGivenOut(
        IPoolSwapStructs.SwapRequestGivenOut calldata swapRequest,
        uint256,
        uint256
    ) external override view returns (uint256) {
        uint256 amountIn = swapRequest.amountOut.div(_multiplier);
        return amountIn;
    }
}
