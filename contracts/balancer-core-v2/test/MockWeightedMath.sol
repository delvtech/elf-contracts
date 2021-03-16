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

import "../pools/weighted/WeightedMath.sol";

contract MockWeightedMath is WeightedMath {
    function invariant(uint256[] calldata normalizedWeights, uint256[] calldata balances)
        external
        pure
        returns (uint256)
    {
        return _invariant(normalizedWeights, balances);
    }

    function outGivenIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountIn
    ) external pure returns (uint256) {
        return _outGivenIn(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn);
    }

    function inGivenOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountOut
    ) external pure returns (uint256) {
        return _inGivenOut(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountOut);
    }

    function exactTokensInForBPTOut(
        uint256[] calldata balances,
        uint256[] calldata normalizedWeights,
        uint256[] calldata amountsIn,
        uint256 bptTotalSupply,
        uint256 swapFee
    ) external pure returns (uint256) {
        return _exactTokensInForBPTOut(balances, normalizedWeights, amountsIn, bptTotalSupply, swapFee);
    }

    function tokenInForExactBPTOut(
        uint256 tokenBalance,
        uint256 tokenNormalizedWeight,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 swapFee
    ) external pure returns (uint256) {
        return _tokenInForExactBPTOut(tokenBalance, tokenNormalizedWeight, bptAmountOut, bptTotalSupply, swapFee);
    }

    function exactBPTInForTokenOut(
        uint256 tokenBalance,
        uint256 tokenNormalizedWeight,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 swapFee
    ) external pure returns (uint256) {
        return _exactBPTInForTokenOut(tokenBalance, tokenNormalizedWeight, bptAmountIn, bptTotalSupply, swapFee);
    }

    function exactBPTInForTokensOut(
        uint256[] calldata currentBalances,
        uint256 bptAmountIn,
        uint256 totalBPT
    ) external pure returns (uint256[] memory) {
        return _exactBPTInForTokensOut(currentBalances, bptAmountIn, totalBPT);
    }

    function bptInForExactTokensOut(
        uint256[] calldata balances,
        uint256[] calldata normalizedWeights,
        uint256[] calldata amountsOut,
        uint256 bptTotalSupply,
        uint256 swapFee
    ) external pure returns (uint256) {
        return _bptInForExactTokensOut(balances, normalizedWeights, amountsOut, bptTotalSupply, swapFee);
    }

    function calculateDueTokenProtocolSwapFee(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 previousInvariant,
        uint256 currentInvariant,
        uint256 protocolSwapFeePercentage
    ) external pure returns (uint256) {
        return
            _calculateDueTokenProtocolSwapFee(
                balance,
                normalizedWeight,
                previousInvariant,
                currentInvariant,
                protocolSwapFeePercentage
            );
    }
}
