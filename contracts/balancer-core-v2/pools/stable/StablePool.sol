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

import "../../lib/math/FixedPoint.sol";
import "../../lib/helpers/InputHelpers.sol";

import "../BaseGeneralPool.sol";

import "./StableMath.sol";
import "./StablePoolUserDataHelpers.sol";

contract StablePool is BaseGeneralPool, StableMath {
    using FixedPoint for uint256;
    using StablePoolUserDataHelpers for bytes;

    uint256 private immutable _amplificationParameter;

    uint256 private _lastInvariant;

    enum JoinKind { INIT, EXACT_TOKENS_IN_FOR_BPT_OUT, TOKEN_IN_FOR_EXACT_BPT_OUT }
    enum ExitKind { EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, EXACT_BPT_IN_FOR_TOKENS_OUT, BPT_IN_FOR_EXACT_TOKENS_OUT }

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256 amplificationParameter,
        uint256 swapFee,
        uint256 emergencyPeriod,
        uint256 emergencyPeriodCheckExtension
    ) BaseGeneralPool(vault, name, symbol, tokens, swapFee, emergencyPeriod, emergencyPeriodCheckExtension) {
        _require(amplificationParameter >= _MIN_AMP, Errors.MIN_AMP);
        _require(amplificationParameter <= _MAX_AMP, Errors.MAX_AMP);

        _require(tokens.length <= _MAX_STABLE_TOKENS, Errors.MAX_STABLE_TOKENS);

        _amplificationParameter = amplificationParameter;
    }

    function getAmplificationParameter() external view returns (uint256) {
        return _amplificationParameter;
    }

    // Base Pool handlers

    // Swap

    function _onSwapGivenIn(
        SwapRequest memory swapRequest,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut
    ) internal view virtual override noEmergencyPeriod returns (uint256) {
        uint256 amountOut = StableMath._calcOutGivenIn(
            _amplificationParameter,
            balances,
            indexIn,
            indexOut,
            swapRequest.amount
        );

        return amountOut;
    }

    function _onSwapGivenOut(
        SwapRequest memory swapRequest,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut
    ) internal view virtual override noEmergencyPeriod returns (uint256) {
        uint256 amountIn = StableMath._calcInGivenOut(
            _amplificationParameter,
            balances,
            indexIn,
            indexOut,
            swapRequest.amount
        );

        return amountIn;
    }

    // Initialize

    function _onInitializePool(
        bytes32,
        address,
        address,
        bytes memory userData
    ) internal virtual override noEmergencyPeriod returns (uint256, uint256[] memory) {
        StablePool.JoinKind kind = userData.joinKind();
        _require(kind == StablePool.JoinKind.INIT, Errors.UNINITIALIZED);

        uint256[] memory amountsIn = userData.initialAmountsIn();
        InputHelpers.ensureInputLengthMatch(amountsIn.length, _totalTokens);
        _upscaleArray(amountsIn, _scalingFactors());

        uint256 invariantAfterJoin = StableMath._calculateInvariant(_amplificationParameter, amountsIn);
        uint256 bptAmountOut = invariantAfterJoin;

        _lastInvariant = invariantAfterJoin;

        return (bptAmountOut, amountsIn);
    }

    // Join

    function _onJoinPool(
        bytes32,
        address,
        address,
        uint256[] memory balances,
        uint256,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    )
        internal
        virtual
        override
        noEmergencyPeriod
        returns (
            uint256,
            uint256[] memory,
            uint256[] memory
        )
    {
        // Due protocol swap fees are computed by measuring the growth of the invariant from the previous join or exit
        // event and now - the invariant's growth is due exclusively to swap fees.
        uint256[] memory dueProtocolFeeAmounts = _getDueProtocolFeeAmounts(
            balances,
            _lastInvariant,
            protocolSwapFeePercentage
        );

        // Update the balances by subtracting the protocol fees that will be charged by the Vault once this function
        // returns.
        for (uint256 i = 0; i < _totalTokens; ++i) {
            balances[i] = balances[i].sub(dueProtocolFeeAmounts[i]);
        }

        (uint256 bptAmountOut, uint256[] memory amountsIn) = _doJoin(balances, userData);

        // Update the invariant with the balances the Pool will have after the join, in order to compute the due
        // protocol swap fees in future joins and exits.
        _lastInvariant = _invariantAfterJoin(balances, amountsIn);

        return (bptAmountOut, amountsIn, dueProtocolFeeAmounts);
    }

    function _doJoin(uint256[] memory balances, bytes memory userData)
        private
        view
        returns (uint256, uint256[] memory)
    {
        JoinKind kind = userData.joinKind();

        if (kind == JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT) {
            return _joinExactTokensInForBPTOut(balances, userData);
        } else if (kind == JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT) {
            return _joinTokenInForExactBPTOut(balances, userData);
        } else {
            _revert(Errors.UNHANDLED_JOIN_KIND);
        }
    }

    function _joinExactTokensInForBPTOut(uint256[] memory balances, bytes memory userData)
        private
        view
        returns (uint256, uint256[] memory)
    {
        (uint256[] memory amountsIn, uint256 minBPTAmountOut) = userData.exactTokensInForBptOut();
        InputHelpers.ensureInputLengthMatch(_totalTokens, amountsIn.length);
        _upscaleArray(amountsIn, _scalingFactors());

        uint256 bptAmountOut = StableMath._calcBptOutGivenExactTokensIn(
            _amplificationParameter,
            balances,
            amountsIn,
            totalSupply(),
            _swapFee
        );

        _require(bptAmountOut >= minBPTAmountOut, Errors.BPT_OUT_MIN_AMOUNT);

        return (bptAmountOut, amountsIn);
    }

    function _joinTokenInForExactBPTOut(uint256[] memory balances, bytes memory userData)
        private
        view
        returns (uint256, uint256[] memory)
    {
        (uint256 bptAmountOut, uint256 tokenIndex) = userData.tokenInForExactBptOut();

        uint256 amountIn = StableMath._calcTokenInGivenExactBptOut(
            _amplificationParameter,
            balances,
            tokenIndex,
            bptAmountOut,
            totalSupply(),
            _swapFee
        );

        // We join in a single token, so we initialize downscaledAmountsIn with zeros and
        // set only downscaledAmountsIn[tokenIndex]
        uint256[] memory downscaledAmountsIn = new uint256[](_totalTokens);
        downscaledAmountsIn[tokenIndex] = amountIn;

        return (bptAmountOut, downscaledAmountsIn);
    }

    // Exit

    function _onExitPool(
        bytes32,
        address,
        address,
        uint256[] memory balances,
        uint256,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    )
        internal
        virtual
        override
        returns (
            uint256 bptAmountIn,
            uint256[] memory amountsOut,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        //If emergency period is active, protocol fees are not charged to avoid any extra calculation.
        if (_isEmergencyPeriodInactive()) {
            // Due protocol swap fees are computed by measuring the growth of the invariant from the previous
            // join or exit event and now - the invariant's growth is due exclusively to swap fees.
            dueProtocolFeeAmounts = _getDueProtocolFeeAmounts(balances, _lastInvariant, protocolSwapFeePercentage);

            // Update the balances by subtracting the protocol fees that will be charged by the Vault once this function
            // returns.
            for (uint256 i = 0; i < _totalTokens; ++i) {
                balances[i] = balances[i].sub(dueProtocolFeeAmounts[i]);
            }
        } else {
            dueProtocolFeeAmounts = new uint256[](_totalTokens);
        }

        (bptAmountIn, amountsOut) = _doExit(balances, userData);

        // Update the invariant with the balances the Pool will have after the exit, in order to compute the due
        // protocol swap fees in future joins and exits.
        _lastInvariant = _invariantAfterExit(balances, amountsOut);

        return (bptAmountIn, amountsOut, dueProtocolFeeAmounts);
    }

    function _doExit(uint256[] memory balances, bytes memory userData)
        private
        view
        returns (uint256, uint256[] memory)
    {
        ExitKind kind = userData.exitKind();

        if (kind == ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT) {
            return _exitExactBPTInForTokenOut(balances, userData);
        } else if (kind == ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT) {
            return _exitExactBPTInForTokensOut(balances, userData);
        } else if (kind == ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT) {
            return _exitBPTInForExactTokensOut(balances, userData);
        } else {
            _revert(Errors.UNHANDLED_EXIT_KIND);
        }
    }

    function _exitExactBPTInForTokenOut(uint256[] memory balances, bytes memory userData)
        private
        view
        noEmergencyPeriod
        returns (uint256, uint256[] memory)
    {
        (uint256 bptAmountIn, uint256 tokenIndex) = userData.exactBptInForTokenOut();
        _require(tokenIndex < _totalTokens, Errors.OUT_OF_BOUNDS);

        // We exit in a single token, so we initialize amountsOut with zeros
        uint256[] memory amountsOut = new uint256[](_totalTokens);

        amountsOut[tokenIndex] = StableMath._calcTokenOutGivenExactBptIn(
            _amplificationParameter,
            balances,
            tokenIndex,
            bptAmountIn,
            totalSupply(),
            _swapFee
        );

        return (bptAmountIn, amountsOut);
    }

    /**
     * @dev Note we are not tagging this function with `noEmergencyPeriod` to allow users to exit in a proportional
     * manner in case there is an emergency in the pool. This operation should never be restricted.
     */
    function _exitExactBPTInForTokensOut(uint256[] memory balances, bytes memory userData)
        private
        view
        returns (uint256, uint256[] memory)
    {
        uint256 bptAmountIn = userData.exactBptInForTokensOut();

        uint256[] memory amountsOut = StableMath._calcTokensOutGivenExactBptIn(balances, bptAmountIn, totalSupply());

        return (bptAmountIn, amountsOut);
    }

    function _exitBPTInForExactTokensOut(uint256[] memory balances, bytes memory userData)
        private
        view
        noEmergencyPeriod
        returns (uint256, uint256[] memory)
    {
        (uint256[] memory amountsOut, uint256 maxBPTAmountIn) = userData.bptInForExactTokensOut();
        InputHelpers.ensureInputLengthMatch(amountsOut.length, _totalTokens);

        _upscaleArray(amountsOut, _scalingFactors());

        uint256 bptAmountIn = StableMath._calcBptInGivenExactTokensOut(
            _amplificationParameter,
            balances,
            amountsOut,
            totalSupply(),
            _swapFee
        );

        _require(bptAmountIn <= maxBPTAmountIn, Errors.BPT_IN_MAX_AMOUNT);

        return (bptAmountIn, amountsOut);
    }

    // Helpers

    function _getDueProtocolFeeAmounts(
        uint256[] memory balances,
        uint256 previousInvariant,
        uint256 protocolSwapFeePercentage
    ) private view returns (uint256[] memory) {
        // Initialize with zeros
        uint256[] memory dueProtocolFeeAmounts = new uint256[](_totalTokens);

        // Early exit in case there is no protocol swap fee
        if (protocolSwapFeePercentage == 0) {
            return dueProtocolFeeAmounts;
        }

        // Instead of paying the protocol swap fee in all tokens proportionally, we will pay it in a single one. This
        // will reduce gas costs for single asset joins and exits, as at most only two Pool balances will change (the
        // token joined/exited, and the token in which fees will be paid).

        // The protocol fee is charged using the token with max balance in the pool.
        uint256 chosenTokenIndex = 0;
        uint256 maxBalance = balances[0];
        for (uint256 i = 1; i < _totalTokens; ++i) {
            uint256 currentBalance = balances[i];
            if (currentBalance > maxBalance) {
                chosenTokenIndex = i;
                maxBalance = currentBalance;
            }
        }

        // Set the fee to pay in the selected token
        dueProtocolFeeAmounts[chosenTokenIndex] = StableMath._calcDueTokenProtocolSwapFee(
            _amplificationParameter,
            balances,
            previousInvariant,
            chosenTokenIndex,
            protocolSwapFeePercentage
        );

        return dueProtocolFeeAmounts;
    }

    function _invariantAfterJoin(uint256[] memory balances, uint256[] memory amountsIn) private view returns (uint256) {
        for (uint256 i = 0; i < _totalTokens; ++i) {
            balances[i] = balances[i].add(amountsIn[i]);
        }

        return StableMath._calculateInvariant(_amplificationParameter, balances);
    }

    function _invariantAfterExit(uint256[] memory balances, uint256[] memory amountsOut)
        private
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < _totalTokens; ++i) {
            balances[i] = balances[i].sub(amountsOut[i]);
        }

        return StableMath._calculateInvariant(_amplificationParameter, balances);
    }

    // This function returns the appreciation of one BPT relative to the
    // underlying tokens. This starts at 1 when the pool is initialized, and grows over time
    // It's equivalent to Curve's get_virtual_price() function
    function getRate() public view override returns (uint256) {
        (, uint256[] memory balances) = _vault.getPoolTokens(_poolId);
        return StableMath._calculateInvariant(_amplificationParameter, balances).div(totalSupply());
    }
}
