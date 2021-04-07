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

import "../lib/math/Math.sol";
import "../lib/helpers/BalancerErrors.sol";
import "../lib/helpers/InputHelpers.sol";
import "../lib/helpers/ReentrancyGuard.sol";
import "../lib/openzeppelin/Address.sol";
import "../lib/openzeppelin/SafeERC20.sol";

import "./interfaces/IBasePool.sol";
import "./InternalBalance.sol";
import "./balances/BalanceAllocation.sol";
import "./balances/GeneralPoolsBalance.sol";
import "./balances/MinimalSwapInfoPoolsBalance.sol";
import "./balances/TwoTokenPoolsBalance.sol";

abstract contract PoolAssets is
    ReentrancyGuard,
    InternalBalance,
    GeneralPoolsBalance,
    MinimalSwapInfoPoolsBalance,
    TwoTokenPoolsBalance
{
    using Math for uint256;
    using SafeERC20 for IERC20;
    using BalanceAllocation for bytes32;
    using BalanceAllocation for bytes32[];

    // Stores the Asset Manager for each token of each Pool.
    mapping(bytes32 => mapping(IERC20 => address)) private _poolAssetManagers;

    function getPoolTokens(bytes32 poolId)
        external
        view
        override
        withRegisteredPool(poolId)
        returns (IERC20[] memory tokens, uint256[] memory balances)
    {
        bytes32[] memory rawBalances;
        (tokens, rawBalances) = _getPoolTokens(poolId);
        balances = rawBalances.totals();
    }

    function getPoolTokenInfo(bytes32 poolId, IERC20 token)
        external
        view
        override
        withRegisteredPool(poolId)
        returns (
            uint256 cash,
            uint256 managed,
            uint256 blockNumber,
            address assetManager
        )
    {
        bytes32 balance;
        PoolSpecialization specialization = _getPoolSpecialization(poolId);

        if (specialization == PoolSpecialization.TWO_TOKEN) {
            balance = _getTwoTokenPoolBalance(poolId, token);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            balance = _getMinimalSwapInfoPoolBalance(poolId, token);
        } else {
            balance = _getGeneralPoolBalance(poolId, token);
        }

        cash = balance.cash();
        managed = balance.managed();
        blockNumber = balance.blockNumber();
        assetManager = _poolAssetManagers[poolId][token];
    }

    function getPool(bytes32 poolId)
        external
        view
        override
        withRegisteredPool(poolId)
        returns (address, PoolSpecialization)
    {
        return (_getPoolAddress(poolId), _getPoolSpecialization(poolId));
    }

    function registerTokens(
        bytes32 poolId,
        IERC20[] calldata tokens,
        address[] calldata assetManagers
    ) external override nonReentrant noEmergencyPeriod onlyPool(poolId) {
        InputHelpers.ensureInputLengthMatch(tokens.length, assetManagers.length);

        // Validates token addresses and assign asset managers
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            _require(Address.isContract(address(token)), Errors.TOKEN_NOT_CONTRACT);
            _poolAssetManagers[poolId][token] = assetManagers[i];
        }

        PoolSpecialization specialization = _getPoolSpecialization(poolId);
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            _require(tokens.length == 2, Errors.TOKENS_LENGTH_MUST_BE_2);
            _registerTwoTokenPoolTokens(poolId, tokens[0], tokens[1]);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            _registerMinimalSwapInfoPoolTokens(poolId, tokens);
        } else {
            _registerGeneralPoolTokens(poolId, tokens);
        }

        emit TokensRegistered(poolId, tokens, assetManagers);
    }

    function deregisterTokens(bytes32 poolId, IERC20[] calldata tokens)
        external
        override
        nonReentrant
        noEmergencyPeriod
        onlyPool(poolId)
    {
        PoolSpecialization specialization = _getPoolSpecialization(poolId);
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            _require(tokens.length == 2, Errors.TOKENS_LENGTH_MUST_BE_2);
            _deregisterTwoTokenPoolTokens(poolId, tokens[0], tokens[1]);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            _deregisterMinimalSwapInfoPoolTokens(poolId, tokens);
        } else {
            _deregisterGeneralPoolTokens(poolId, tokens);
        }

        // The deregister calls above ensure the total token balance is zero. Therefore it is now safe to remove any
        // associated Asset Managers, since they hold no Pool balance.
        for (uint256 i = 0; i < tokens.length; ++i) {
            delete _poolAssetManagers[poolId][tokens[i]];
        }

        emit TokensDeregistered(poolId, tokens);
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable override {
        _joinOrExit(PoolBalanceChangeKind.JOIN, poolId, sender, recipient, _toPoolBalanceChange(request));
    }

    /**
     * @dev Converts a JoinPoolRequest into a PoolBalanceChange, with no runtime cost.
     */
    function _toPoolBalanceChange(JoinPoolRequest memory request)
        private
        pure
        returns (PoolBalanceChange memory change)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            change := request
        }
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external override {
        _joinOrExit(PoolBalanceChangeKind.EXIT, poolId, sender, recipient, _toPoolBalanceChange(request));
    }

    /**
     * @dev Converts a ExitPoolRequest into a PoolBalanceChange, with no runtime cost.
     */
    function _toPoolBalanceChange(ExitPoolRequest memory request)
        private
        pure
        returns (PoolBalanceChange memory change)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            change := request
        }
    }

    function _joinOrExit(
        PoolBalanceChangeKind kind,
        bytes32 poolId,
        address sender,
        address recipient,
        PoolBalanceChange memory change
    ) internal nonReentrant noEmergencyPeriod withRegisteredPool(poolId) authenticateFor(sender) {
        InputHelpers.ensureInputLengthMatch(change.assets.length, change.limits.length);

        IERC20[] memory tokens = _translateToIERC20(change.assets);
        bytes32[] memory balances = _validateTokensAndGetBalances(poolId, tokens);
        (
            bytes32[] memory finalBalances,
            uint256[] memory amounts,
            uint256[] memory dueProtocolFeeAmounts
        ) = _callPoolBalanceChange(kind, poolId, sender, recipient, change, balances);

        // Update the Pool's balance - how this is done depends on the Pool specialization setting.
        PoolSpecialization specialization = _getPoolSpecialization(poolId);
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            _setTwoTokenPoolCashBalances(poolId, tokens[0], finalBalances[0], tokens[1], finalBalances[1]);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            _setMinimalSwapInfoPoolBalances(poolId, tokens, finalBalances);
        } else {
            _setGeneralPoolBalances(poolId, finalBalances);
        }

        // We can unsafely cast to int256 because balances are actually stored as uint112
        bool positive = kind == PoolBalanceChangeKind.JOIN;
        emit PoolBalanceChanged(poolId, sender, tokens, _unsafeCastToInt256(amounts, positive), dueProtocolFeeAmounts);
    }

    function _callPoolBalanceChange(
        PoolBalanceChangeKind kind,
        bytes32 poolId,
        address sender,
        address recipient,
        PoolBalanceChange memory change,
        bytes32[] memory balances
    )
        internal
        returns (
            bytes32[] memory finalBalances,
            uint256[] memory amounts,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        (uint256[] memory totalBalances, uint256 latestBlockNumberUsed) = balances.totalsAndMaxBlockNumber();

        IBasePool pool = IBasePool(_getPoolAddress(poolId));
        (amounts, dueProtocolFeeAmounts) = kind == PoolBalanceChangeKind.JOIN
            ? pool.onJoinPool(
                poolId,
                sender,
                recipient,
                totalBalances,
                latestBlockNumberUsed,
                _getProtocolSwapFee(),
                change.userData
            )
            : pool.onExitPool(
                poolId,
                sender,
                recipient,
                totalBalances,
                latestBlockNumberUsed,
                _getProtocolSwapFee(),
                change.userData
            );

        InputHelpers.ensureInputLengthMatch(balances.length, amounts.length, dueProtocolFeeAmounts.length);

        finalBalances = kind == PoolBalanceChangeKind.JOIN
            ? _receiveAssets(sender, change, balances, amounts, dueProtocolFeeAmounts)
            : _sendAssets(payable(recipient), change, balances, amounts, dueProtocolFeeAmounts);
    }

    /**
     * @dev Returns the total balance for `poolId`'s `expectedTokens`.
     *
     * `expectedTokens` must exactly equal the token array returned by `getPoolTokens`: both arrays must have the same
     * length, elements and order.
     */
    function _validateTokensAndGetBalances(bytes32 poolId, IERC20[] memory expectedTokens)
        internal
        view
        returns (bytes32[] memory)
    {
        (IERC20[] memory actualTokens, bytes32[] memory balances) = _getPoolTokens(poolId);
        InputHelpers.ensureInputLengthMatch(actualTokens.length, expectedTokens.length);

        for (uint256 i = 0; i < actualTokens.length; ++i) {
            _require(actualTokens[i] == expectedTokens[i], Errors.TOKENS_MISMATCH);
        }

        return balances;
    }

    // Assets under management

    function managePoolBalance(
        bytes32 poolId,
        AssetManagerOpKind kind,
        AssetManagerTransfer[] memory transfers
    ) external override nonReentrant noEmergencyPeriod {
        _ensureRegisteredPool(poolId);
        PoolSpecialization specialization = _getPoolSpecialization(poolId);

        for (uint256 i = 0; i < transfers.length; ++i) {
            IERC20 token = transfers[i].token;
            _ensurePoolAssetManagerIsSender(poolId, token);
            uint256 amount = transfers[i].amount;

            int256 delta;
            if (kind == AssetManagerOpKind.DEPOSIT) {
                delta = _depositPoolBalance(poolId, specialization, token, amount);
            } else if (kind == AssetManagerOpKind.WITHDRAW) {
                delta = _withdrawPoolBalance(poolId, specialization, token, amount);
            } else {
                delta = _updateManagedBalance(poolId, specialization, token, amount);
            }

            emit PoolBalanceManaged(poolId, msg.sender, token, delta);
        }
    }

    function _withdrawPoolBalance(
        bytes32 poolId,
        PoolSpecialization specialization,
        IERC20 token,
        uint256 amount
    ) private returns (int256) {
        if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            _minimalSwapInfoPoolCashToManaged(poolId, token, amount);
        } else if (specialization == PoolSpecialization.TWO_TOKEN) {
            _twoTokenPoolCashToManaged(poolId, token, amount);
        } else {
            _generalPoolCashToManaged(poolId, token, amount);
        }

        token.safeTransfer(msg.sender, amount);

        // Due to how balances are stored internally we know `amount` will always fit in an int256
        return -int256(amount);
    }

    function _depositPoolBalance(
        bytes32 poolId,
        PoolSpecialization specialization,
        IERC20 token,
        uint256 amount
    ) private returns (int256) {
        if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            _minimalSwapInfoPoolManagedToCash(poolId, token, amount);
        } else if (specialization == PoolSpecialization.TWO_TOKEN) {
            _twoTokenPoolManagedToCash(poolId, token, amount);
        } else {
            _generalPoolManagedToCash(poolId, token, amount);
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        // Due to how balances are stored internally we know `amount` will always fit in an int256
        return int256(amount);
    }

    function _updateManagedBalance(
        bytes32 poolId,
        PoolSpecialization specialization,
        IERC20 token,
        uint256 amount
    ) private returns (int256) {
        if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            return _setMinimalSwapInfoPoolManagedBalance(poolId, token, amount);
        } else if (specialization == PoolSpecialization.TWO_TOKEN) {
            return _setTwoTokenPoolManagedBalance(poolId, token, amount);
        } else {
            return _setGeneralPoolManagedBalance(poolId, token, amount);
        }
    }

    /**
     * @dev Returns all of `poolId`'s registered tokens, along with their raw balances.
     */
    function _getPoolTokens(bytes32 poolId) internal view returns (IERC20[] memory tokens, bytes32[] memory balances) {
        PoolSpecialization specialization = _getPoolSpecialization(poolId);
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            return _getTwoTokenPoolTokens(poolId);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            return _getMinimalSwapInfoPoolTokens(poolId);
        } else {
            return _getGeneralPoolTokens(poolId);
        }
    }

    function _receiveAssets(
        address sender,
        PoolBalanceChange memory change,
        bytes32[] memory balances,
        uint256[] memory amountsIn,
        uint256[] memory dueProtocolFeeAmounts
    ) private returns (bytes32[] memory finalBalances) {
        uint256 wrappedEth = 0;

        finalBalances = new bytes32[](balances.length);
        for (uint256 i = 0; i < change.assets.length; ++i) {
            uint256 amountIn = amountsIn[i];
            _require(amountIn <= change.limits[i], Errors.JOIN_ABOVE_MAX);

            // Receive assets from the caller - possibly from Internal Balance
            IAsset asset = change.assets[i];
            _receiveAsset(asset, amountIn, sender, change.useInternalBalance);

            if (_isETH(asset)) {
                wrappedEth = wrappedEth.add(amountIn);
            }

            uint256 feeToPay = dueProtocolFeeAmounts[i];

            // Compute the new Pool balances. Note that due protocol fees might be larger than amounts in,
            // resulting in an overall decrease of the Pool's balance for a token.
            finalBalances[i] = (amountIn >= feeToPay)
                ? balances[i].increaseCash(amountIn - feeToPay) // Don't need checked arithmetic
                : balances[i].decreaseCash(feeToPay - amountIn); // Same as -(int256(amountIn) - int256(feeToPay))

            _payFee(_translateToIERC20(asset), feeToPay);
        }

        // Handle any used and remaining ETH.
        _handleRemainingEth(wrappedEth);
    }

    function _sendAssets(
        address payable recipient,
        PoolBalanceChange memory change,
        bytes32[] memory balances,
        uint256[] memory amountsOut,
        uint256[] memory dueProtocolFeeAmounts
    ) private returns (bytes32[] memory finalBalances) {
        finalBalances = new bytes32[](balances.length);
        for (uint256 i = 0; i < change.assets.length; ++i) {
            uint256 amountOut = amountsOut[i];
            _require(amountOut >= change.limits[i], Errors.EXIT_BELOW_MIN);

            // Send tokens to the recipient - possibly to Internal Balance
            IAsset asset = change.assets[i];
            _sendAsset(asset, amountOut, recipient, change.useInternalBalance);

            uint256 protocolSwapFee = dueProtocolFeeAmounts[i];

            // Compute the new Pool balances. A Pool's token balance always decreases after an exit (potentially by 0).
            uint256 delta = amountOut.add(protocolSwapFee);
            finalBalances[i] = balances[i].decreaseCash(delta);

            _payFee(_translateToIERC20(asset), protocolSwapFee);
        }
    }

    /**
     * @dev Reverts unless `poolId` corresponds to a registered Pool, `token` is registered for that Pool, and the
     * caller is the Pool's Asset Manager for `token`.
     */
    function _ensurePoolAssetManagerIsSender(bytes32 poolId, IERC20 token) private view {
        _ensureTokenRegistered(poolId, token);
        _require(_poolAssetManagers[poolId][token] == msg.sender, Errors.SENDER_NOT_ASSET_MANAGER);
    }

    /**
     * @dev Reverts unless `token` is registered for `poolId`.
     */
    function _ensureTokenRegistered(bytes32 poolId, IERC20 token) private view {
        _require(_isTokenRegistered(poolId, token), Errors.TOKEN_NOT_REGISTERED);
    }

    /**
     * @dev Returns true if `token` is registered for `poolId`.
     */
    function _isTokenRegistered(bytes32 poolId, IERC20 token) private view returns (bool) {
        PoolSpecialization specialization = _getPoolSpecialization(poolId);
        if (specialization == PoolSpecialization.TWO_TOKEN) {
            return _isTwoTokenPoolTokenRegistered(poolId, token);
        } else if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            return _isMinimalSwapInfoPoolTokenRegistered(poolId, token);
        } else {
            return _isGeneralPoolTokenRegistered(poolId, token);
        }
    }

    /**
     * @dev Casts an array of uint256 to int256 without checking overflows
     */
    function _unsafeCastToInt256(uint256[] memory values, bool positive) private pure returns (int256[] memory casts) {
        casts = new int256[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            casts[i] = positive ? int256(values[i]) : -int256(values[i]);
        }
    }
}
