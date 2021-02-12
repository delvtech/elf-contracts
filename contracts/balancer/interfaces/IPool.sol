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

pragma solidity >=0.7.1;
pragma experimental ABIEncoderV2;

import "./IVault.sol";

interface IPool {
    function getVault() external view returns (IVault);

    function getPoolId() external view returns (bytes32);

    /**
     * @dev Called by the Vault when a user calls `IVault.joinPool`. The Pool must return how many tokens the user
     * should provide for each registered token, as well as how many protocol fees the Pool owes to the Vault. After
     * returning, the Vault will take tokens from the `sender` and add it to the Pool's balance, as well as collect
     * reported protocol fees.
     *
     * Due protocol fees are reported and charged on join events so that new users join the Pool free of debt.
     *
     * `sender` is the account performing the join (from whom tokens will be withdrawn), and `recipient` an account
     * designated to receive any benefits (typically pool shares). `currentBalances` contains the total token balances
     * for each token the Pool registered in the Vault, in the same order as found there.
     *
     * Contracts implementing this should check that the caller is indeed the Vault before performing any state-changing
     * operations, such as minting pool shares.
     */
    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] calldata currentBalances,
        uint256[] calldata maxAmountsIn,
        uint256 protocolSwapFee,
        bytes calldata userData
    )
        external
        returns (
            uint256[] memory amountsIn,
            uint256[] memory dueProtocolFeeAmounts
        );

    /**
     * @dev Called by the Vault when a user calls `IVault.exitPool`. The Pool must return how many tokens the Vault
     * should deduct from the Pool, as well as how many protocol fees the Pool owes to the Vault. After returning, the
     * Vault will take tokens from the Pool's balance and add grant them to `recipient`, as well as collect reported
     * protocol fees.
     *
     * Due protocol fees are reported and charged on exit events so that users exit the Pool having paid all debt.
     *
     * `sender` is the account performing the exit (typically the holder of pool shares), and `recipient` the account to
     * which the Vault will grant tokens. `currentBalances` contains the total token balances for each token the Pool
     * registered in the Vault, in the same order as found there.
     *
     * Contracts implementing this should check that the caller is indeed the Vault before performing any state-changing
     * operations, such as burning pool shares.
     */
    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] calldata currentBalances,
        uint256[] calldata minAmountsOut,
        uint256 protocolSwapFee,
        bytes calldata userData
    )
        external
        returns (
            uint256[] memory amountsOut,
            uint256[] memory dueProtocolFeeAmounts
        );
}
