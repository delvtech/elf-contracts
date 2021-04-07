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
import "../lib/helpers/EnumerableMap.sol";
import "../lib/helpers/InputHelpers.sol";
import "../lib/helpers/ReentrancyGuard.sol";
import "../lib/openzeppelin/SafeCast.sol";
import "../lib/openzeppelin/SafeERC20.sol";
import "../lib/openzeppelin/EnumerableSet.sol";

import "./PoolAssets.sol";
import "./interfaces/IPoolSwapStructs.sol";
import "./interfaces/IGeneralPool.sol";
import "./interfaces/IMinimalSwapInfoPool.sol";
import "./balances/BalanceAllocation.sol";

abstract contract Swaps is ReentrancyGuard, PoolAssets {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;

    using Math for int256;
    using Math for uint256;
    using SafeCast for uint256;
    using BalanceAllocation for bytes32;

    // Despite the external API having two separate functions for given in and given out, internally they are handled
    // together to avoid unnecessary code duplication. This enum indicates which kind of swap we're processing.

    // We use inline assembly to convert arrays of different struct types that have the same underlying data
    // representation. This doesn't trigger any actual conversions or runtime analysis: it is just coercing the type
    // system to reinterpret the data as another type.

    /**
     * @dev Converts an array of `SwapIn` into an array of `SwapRequest`, with no runtime cost.
     */
    function _toSwapRequests(SwapIn[] memory swapsIn) private pure returns (SwapRequest[] memory swapRequests) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            swapRequests := swapsIn
        }
    }

    /**
     * @dev Converts an array of `SwapOut` into an array of `InternalSwap`, with no runtime cost.
     */
    function _toSwapRequests(SwapOut[] memory swapsOut) private pure returns (SwapRequest[] memory swapRequests) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            swapRequests := swapsOut
        }
    }

    // This struct is identical in layout to IPoolSwapStructs.SwapRequest
    struct InternalSwapRequest {
        SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amount;
        bytes32 poolId;
        uint256 latestBlockNumberUsed;
        address from;
        address to;
        bytes userData;
    }

    /**
     * @dev Converts an InternalSwapRequest into a Pool SwapRequest, with no runtime cost.
     */
    function _toPoolSwapRequest(InternalSwapRequest memory internalSwapRequest)
        private
        pure
        returns (IPoolSwapStructs.SwapRequest memory swapRequest)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            swapRequest := internalSwapRequest
        }
    }

    function swap(
        SingleSwap memory request,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable override nonReentrant noEmergencyPeriod authenticateFor(funds.sender) returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        _require(block.timestamp <= deadline, Errors.SWAP_DEADLINE);

        uint256 amountGiven = request.amount;
        _require(amountGiven > 0, Errors.UNKNOWN_AMOUNT_IN_FIRST_SWAP);

        IERC20 tokenIn = _translateToIERC20(request.assetIn);
        IERC20 tokenOut = _translateToIERC20(request.assetOut);
        _require(tokenIn != tokenOut, Errors.CANNOT_SWAP_SAME_TOKEN);
        // Initializing each struct field one-by-one uses less gas than setting all at once
        InternalSwapRequest memory internalRequest;
        internalRequest.poolId = request.poolId;
        internalRequest.kind = request.kind;
        internalRequest.tokenIn = tokenIn;
        internalRequest.tokenOut = tokenOut;
        internalRequest.amount = amountGiven;
        internalRequest.userData = request.userData;
        internalRequest.from = funds.sender;
        internalRequest.to = funds.recipient;

        uint256 amountCalculated = _swapWithPool(internalRequest);
        (uint256 amountIn, uint256 amountOut) = _getAmounts(request.kind, amountGiven, amountCalculated);
        _require(request.kind == SwapKind.GIVEN_IN ? amountOut >= limit : amountIn <= limit, Errors.SWAP_LIMIT);

        // Receive token in
        _receiveAsset(request.assetIn, amountIn, funds.sender, funds.fromInternalBalance);

        // Send token out
        _sendAsset(request.assetOut, amountOut, funds.recipient, funds.toInternalBalance);

        // Handle any used and remaining ETH.
        _handleRemainingEth(_isETH(request.assetIn) ? amountIn : 0);

        emit Swap(request.poolId, tokenIn, tokenOut, amountIn, amountOut);
        return amountCalculated;
    }

    function batchSwapGivenIn(
        SwapIn[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable override nonReentrant noEmergencyPeriod authenticateFor(funds.sender) returns (int256[] memory) {
        return _batchSwap(_toSwapRequests(swaps), assets, funds, limits, deadline, SwapKind.GIVEN_IN);
    }

    function batchSwapGivenOut(
        SwapOut[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable override nonReentrant noEmergencyPeriod authenticateFor(funds.sender) returns (int256[] memory) {
        return _batchSwap(_toSwapRequests(swaps), assets, funds, limits, deadline, SwapKind.GIVEN_OUT);
    }

    /**
     * @dev Implements both `batchSwapGivenIn` and `batchSwapGivenIn`, depending on the `kind` value.
     */
    function _batchSwap(
        SwapRequest[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline,
        SwapKind kind
    ) private returns (int256[] memory assetDeltas) {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        _require(block.timestamp <= deadline, Errors.SWAP_DEADLINE);

        InputHelpers.ensureInputLengthMatch(assets.length, limits.length);

        // Perform the swaps, updating the Pool token balances and computing the net Vault asset deltas.
        assetDeltas = _swapWithPools(swaps, assets, funds, kind);

        // Process asset deltas, by either transferring tokens from the sender (for positive deltas) or to the recipient
        // (for negative deltas).

        uint256 wrappedEth = 0;
        for (uint256 i = 0; i < assets.length; ++i) {
            IAsset asset = assets[i];
            int256 delta = assetDeltas[i];

            _require(delta <= limits[i], Errors.SWAP_LIMIT);

            if (delta > 0) {
                uint256 toReceive = uint256(delta);
                _receiveAsset(asset, toReceive, funds.sender, funds.fromInternalBalance);

                if (_isETH(asset)) {
                    wrappedEth = wrappedEth.add(toReceive);
                }
            } else if (delta < 0) {
                uint256 toSend = uint256(-delta);
                _sendAsset(asset, toSend, funds.recipient, funds.toInternalBalance);
            }
        }

        // Handle any used and remaining ETH.
        _handleRemainingEth(wrappedEth);
    }

    // For `_swapWithPools` to handle both given in and given out swaps, it internally tracks the 'given' amount
    // (supplied by the caller), and the 'calculated' one (returned by the Pool in response to the swap request).

    /**
     * @dev Given the two swap tokens and the swap kind, returns which one is the 'given' token (the one for which the
     * amount is supplied by the caller).
     */
    function _tokenGiven(
        SwapKind kind,
        IERC20 tokenIn,
        IERC20 tokenOut
    ) private pure returns (IERC20) {
        return kind == SwapKind.GIVEN_IN ? tokenIn : tokenOut;
    }

    /**
     * @dev Given the two swap tokens and the swap kind, returns which one is the 'calculated' token (the one for
     * which the amount is calculated by the Pool).
     */
    function _tokenCalculated(
        SwapKind kind,
        IERC20 tokenIn,
        IERC20 tokenOut
    ) private pure returns (IERC20) {
        return kind == SwapKind.GIVEN_IN ? tokenOut : tokenIn;
    }

    /**
     * @dev Returns an ordered pair (amountIn, amountOut) given the amounts given and calculated and the swap kind.
     */
    function _getAmounts(
        SwapKind kind,
        uint256 amountGiven,
        uint256 amountCalculated
    ) private pure returns (uint256 amountIn, uint256 amountOut) {
        if (kind == SwapKind.GIVEN_IN) {
            (amountIn, amountOut) = (amountGiven, amountCalculated);
        } else {
            (amountIn, amountOut) = (amountCalculated, amountGiven);
        }
    }

    /**
     * @dev Performs all `swaps`, calling swap hooks on the Pool contracts and updating their balances. Does not cause
     * any transfer of tokens - instead it returns the net Vault token deltas: positive if the Vault should receive
     * tokens, and negative if it should send them.
     */
    function _swapWithPools(
        SwapRequest[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        SwapKind kind
    ) private returns (int256[] memory assetDeltas) {
        assetDeltas = new int256[](assets.length);

        // This variable could be declared inside the loop, but that causes the compiler to allocate memory on each
        // loop iteration, increasing gas costs.
        SwapRequest memory request;

        // These store data about the previous swap here to implement multihop logic across swaps.
        IERC20 previousTokenCalculated;
        uint256 previousAmountCalculated;

        for (uint256 i = 0; i < swaps.length; ++i) {
            request = swaps[i];
            bool withinBounds = request.tokenInIndex < assets.length && request.tokenOutIndex < assets.length;
            _require(withinBounds, Errors.OUT_OF_BOUNDS);

            IERC20 tokenIn = _translateToIERC20(assets[request.tokenInIndex]);
            IERC20 tokenOut = _translateToIERC20(assets[request.tokenOutIndex]);
            _require(tokenIn != tokenOut, Errors.CANNOT_SWAP_SAME_TOKEN);

            // Sentinel value for multihop logic
            if (request.amount == 0) {
                // When the amount given is zero, we use the calculated amount for the previous swap, as long as the
                // current swap's given token is the previous calculated token. This makes it possible to e.g. swap a
                // given amount of token A for token B, and then use the resulting token B amount to swap for token C.
                _require(i > 0, Errors.UNKNOWN_AMOUNT_IN_FIRST_SWAP);
                bool usingPreviousToken = previousTokenCalculated == _tokenGiven(kind, tokenIn, tokenOut);
                _require(usingPreviousToken, Errors.MALCONSTRUCTED_MULTIHOP_SWAP);
                request.amount = previousAmountCalculated;
            }

            // Initializing each struct field one-by-one uses less gas than setting all at once
            InternalSwapRequest memory internalRequest;
            internalRequest.poolId = request.poolId;
            internalRequest.kind = kind;
            internalRequest.tokenIn = tokenIn;
            internalRequest.tokenOut = tokenOut;
            internalRequest.amount = request.amount;
            internalRequest.userData = request.userData;
            internalRequest.from = funds.sender;
            internalRequest.to = funds.recipient;
            // latestBlockNumberUsed is not set here - that will be done later by the different Pool specialization
            // handlers

            previousAmountCalculated = _swapWithPool(internalRequest);
            previousTokenCalculated = _tokenCalculated(kind, tokenIn, tokenOut);

            (uint256 amountIn, uint256 amountOut) = _getAmounts(kind, request.amount, previousAmountCalculated);
            emit Swap(request.poolId, tokenIn, tokenOut, amountIn, amountOut);

            // Accumulate Vault deltas across swaps
            assetDeltas[request.tokenInIndex] = assetDeltas[request.tokenInIndex].add(amountIn.toInt256());
            assetDeltas[request.tokenOutIndex] = assetDeltas[request.tokenOutIndex].sub(amountOut.toInt256());
        }
    }

    /**
     * @dev Performs `swap`, calling the Pool's contract hook and updating the Pool balance.
     * Returns the amount of tokens going into/out of the Vault as a result of this swap, depending on the swap kind.
     */
    function _swapWithPool(InternalSwapRequest memory request) private returns (uint256) {
        // Get the calculated amount from the Pool and update its balances
        address pool = _getPoolAddress(request.poolId);
        PoolSpecialization specialization = _getPoolSpecialization(request.poolId);

        if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            return _processMinimalSwapInfoPoolSwapRequest(request, IMinimalSwapInfoPool(pool));
        } else if (specialization == PoolSpecialization.TWO_TOKEN) {
            return _processTwoTokenPoolSwapRequest(request, IMinimalSwapInfoPool(pool));
        } else {
            return _processGeneralPoolSwapRequest(request, IGeneralPool(pool));
        }
    }

    function _processTwoTokenPoolSwapRequest(InternalSwapRequest memory request, IMinimalSwapInfoPool pool)
        private
        returns (uint256 amountCalculated)
    {
        // For gas efficiency reasons, this function uses low-level knowledge of how Two Token Pool balances are
        // stored internally, instead of using getters and setters for all operations.

        (
            bytes32 tokenABalance,
            bytes32 tokenBBalance,
            TwoTokenPoolBalances storage poolBalances
        ) = _getTwoTokenPoolSharedBalances(request.poolId, request.tokenIn, request.tokenOut);

        // We have the two Pool balances, but we don't know which one is the token in and which one is the token out.
        bytes32 tokenInBalance;
        bytes32 tokenOutBalance;

        // In Two Token Pools, token A has a smaller address than token B
        if (request.tokenIn < request.tokenOut) {
            // in is A, out is B
            tokenInBalance = tokenABalance;
            tokenOutBalance = tokenBBalance;
        } else {
            // in is B, out is A
            tokenOutBalance = tokenABalance;
            tokenInBalance = tokenBBalance;
        }

        // Perform the swap request and compute the new balances for token in and token out after the swap
        (tokenInBalance, tokenOutBalance, amountCalculated) = _callMinimalSwapInfoPoolOnSwapHook(
            request,
            pool,
            tokenInBalance,
            tokenOutBalance
        );

        // We check the token ordering again to create the new shared cash packed struct
        poolBalances.sharedCash = request.tokenIn < request.tokenOut
            ? BalanceAllocation.toSharedCash(tokenInBalance, tokenOutBalance) // in is A, out is B
            : BalanceAllocation.toSharedCash(tokenOutBalance, tokenInBalance); // in is B, out is A
    }

    function _processMinimalSwapInfoPoolSwapRequest(InternalSwapRequest memory request, IMinimalSwapInfoPool pool)
        private
        returns (uint256 amountCalculated)
    {
        bytes32 tokenInBalance = _getMinimalSwapInfoPoolBalance(request.poolId, request.tokenIn);
        bytes32 tokenOutBalance = _getMinimalSwapInfoPoolBalance(request.poolId, request.tokenOut);

        // Perform the swap request and compute the new balances for token in and token out after the swap
        (tokenInBalance, tokenOutBalance, amountCalculated) = _callMinimalSwapInfoPoolOnSwapHook(
            request,
            pool,
            tokenInBalance,
            tokenOutBalance
        );

        _minimalSwapInfoPoolsBalances[request.poolId][request.tokenIn] = tokenInBalance;
        _minimalSwapInfoPoolsBalances[request.poolId][request.tokenOut] = tokenOutBalance;
    }

    /**
     * @dev Calls the onSwap hook for a Pool that implements IMinimalSwapInfoPool, which are both minimal swap info
     * pools and two token pools.
     */
    function _callMinimalSwapInfoPoolOnSwapHook(
        InternalSwapRequest memory request,
        IMinimalSwapInfoPool pool,
        bytes32 tokenInBalance,
        bytes32 tokenOutBalance
    )
        internal
        returns (
            bytes32 newTokenInBalance,
            bytes32 newTokenOutBalance,
            uint256 amountCalculated
        )
    {
        uint256 tokenInTotal = tokenInBalance.total();
        uint256 tokenOutTotal = tokenOutBalance.total();
        request.latestBlockNumberUsed = Math.max(tokenInBalance.blockNumber(), tokenOutBalance.blockNumber());

        // Perform the swap request callback and compute the new balances for token in and token out after the swap
        IPoolSwapStructs.SwapRequest memory poolSwapRequest = _toPoolSwapRequest(request);
        amountCalculated = pool.onSwap(poolSwapRequest, tokenInTotal, tokenOutTotal);
        (uint256 amountIn, uint256 amountOut) = _getAmounts(request.kind, request.amount, amountCalculated);
        newTokenInBalance = tokenInBalance.increaseCash(amountIn);
        newTokenOutBalance = tokenOutBalance.decreaseCash(amountOut);
    }

    function _processGeneralPoolSwapRequest(InternalSwapRequest memory request, IGeneralPool pool)
        private
        returns (uint256 amountCalculated)
    {
        bytes32 tokenInBalance;
        bytes32 tokenOutBalance;

        // We access both token indexes without checking existence,  because we will do it manually immediately after.
        EnumerableMap.IERC20ToBytes32Map storage poolBalances = _generalPoolsBalances[request.poolId];
        uint256 indexIn = poolBalances.unchecked_indexOf(request.tokenIn);
        uint256 indexOut = poolBalances.unchecked_indexOf(request.tokenOut);

        if (indexIn == 0 || indexOut == 0) {
            // The tokens might not be registered because the Pool itself is not registered. If so, we provide a more
            // accurate revert reason. We only check this at this stage to save gas in the case where the tokens
            // are registered, whicn implies the Pool is as well.
            _ensureRegisteredPool(request.poolId);
            _revert(Errors.TOKEN_NOT_REGISTERED);
        }

        // EnumerableMap stores indices plus one to use the zero index as a sentinel value - because these are valid,
        // we can undo this.
        indexIn -= 1;
        indexOut -= 1;

        uint256 tokenAmount = poolBalances.length();
        uint256[] memory currentBalances = new uint256[](tokenAmount);

        for (uint256 i = 0; i < tokenAmount; i++) {
            // Because the iteration is bounded by `tokenAmount` and no tokens are registered or deregistered here, we
            // can use `unchecked_valueAt` as we know `i` is a valid token index, saving storage reads.
            bytes32 balance = poolBalances.unchecked_valueAt(i);

            currentBalances[i] = balance.total();
            request.latestBlockNumberUsed = Math.max(request.latestBlockNumberUsed, balance.blockNumber());

            if (i == indexIn) {
                tokenInBalance = balance;
            } else if (i == indexOut) {
                tokenOutBalance = balance;
            }
        }

        // Perform the swap request callback and compute the new balances for token in and token out after the swap
        IPoolSwapStructs.SwapRequest memory poolSwapRequest = _toPoolSwapRequest(request);
        amountCalculated = pool.onSwap(poolSwapRequest, currentBalances, indexIn, indexOut);
        (uint256 amountIn, uint256 amountOut) = _getAmounts(request.kind, request.amount, amountCalculated);
        tokenInBalance = tokenInBalance.increaseCash(amountIn);
        tokenOutBalance = tokenOutBalance.decreaseCash(amountOut);

        // Because no tokens were registered or deregistered between now and when we retrieved the indexes for
        // token in and token out, we can use `unchecked_setAt`, saving storage reads.
        poolBalances.unchecked_setAt(indexIn, tokenInBalance);
        poolBalances.unchecked_setAt(indexOut, tokenOutBalance);
    }

    // This function is not marked as `nonReentrant` because the underlying mechanism relies on reentrancy
    function queryBatchSwap(
        SwapKind kind,
        SwapRequest[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds
    ) external override returns (int256[] memory) {
        // In order to accurately 'simulate' swaps, this function actually does perform the swaps, including calling the
        // Pool hooks and updating balances in storage. However, once it computes the final Vault Deltas, it
        // reverts unconditionally, returning this array as the revert data.
        //
        // By wrapping this reverting call, we can decode the deltas 'returned' and return them as a normal Solidity
        // function would. The only caveat is the function becomes non-view, but off-chain clients can still call it
        // via eth_call to get the expected result.
        //
        // This technique was inspired by the work from the Gnosis team in the Gnosis Safe contract:
        // https://github.com/gnosis/safe-contracts/blob/v1.2.0/contracts/GnosisSafe.sol#L265
        //
        // Most of this function is implemented using inline assembly, as the actual work it needs to do is not
        // significant, and Solidity is not particularly well-suited to generate this behavior, resulting in a large
        // amount of generated bytecode.

        if (msg.sender != address(this)) {
            // We perform an external call to ourselves, forwarding the same calldata. In this call, the else clause of
            // the preceding if statement will be executed instead.

            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = address(this).call(msg.data);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // This call should always revert to decode the actual token deltas from the revert reason
                switch success
                    case 0 {
                        // Note we are manually writing the memory slot 0. We can safely overwrite whatever is
                        // stored there as we take full control of the execution and then immediately return.

                        // We copy the first 4 bytes to check if it matches with the expected signature, otherwise
                        // there was another revert reason and we should forward it.
                        returndatacopy(0, 0, 0x04)
                        let error := and(mload(0), 0xffffffff00000000000000000000000000000000000000000000000000000000)

                        // If the first 4 bytes don't match with the expected signature, we forward the revert reason.
                        if eq(eq(error, 0xfa61cc1200000000000000000000000000000000000000000000000000000000), 0) {
                            returndatacopy(0, 0, returndatasize())
                            revert(0, returndatasize())
                        }

                        // The returndata contains the signature, followed by the raw memory representation of an array:
                        // length + data. We need to return an ABI-encoded representation of this array.
                        // An ABI-encoded array contains an additional field when compared to its raw memory
                        // representation: an offset to the location of the length. The offset itself is 32 bytes long,
                        // so the smallest value we  can use is 32 for the data to be located immediately after it.
                        mstore(0, 32)

                        // We now copy the raw memory array from returndata into memory. Since the offset takes up 32
                        // bytes, we start copying at address 0x20. We also get rid of the error signature, which takes
                        // the first four bytes of returndata.
                        let size := sub(returndatasize(), 0x04)
                        returndatacopy(0x20, 0x04, size)

                        // We finally return the ABI-encoded array, which has a total length equal to that of the array
                        // (returndata), plus the 32 bytes for the offset.
                        return(0, add(size, 32))
                    }
                    default {
                        // This call should always revert, but we fail nonetheless if that didn't happen
                        invalid()
                    }
            }
        } else {
            int256[] memory deltas = _swapWithPools(swaps, assets, funds, kind);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // We will return a raw representation of the array in memory, which is composed of a 32 byte length,
                // followed by the 32 byte int256 values. Because revert expects a size in bytes, we multiply the array
                // length (stored at `deltas`) by 32.
                let size := mul(mload(deltas), 32)

                // We send one extra value for the error signature "QueryError(int256[])" which is 0xfa61cc12.
                // We store it in the previous slot to the `deltas` array. We know there will be at least one available
                // slot due to how the memory scratch space works.
                // We can safely overwrite whatever is stored in this slot as we will revert immediately after that.
                mstore(sub(deltas, 0x20), 0x00000000000000000000000000000000000000000000000000000000fa61cc12)
                let start := sub(deltas, 0x04)

                // When copying from `deltas` into returndata, we copy an additional 36 bytes to also return the array's
                // length and the error signature.
                revert(start, add(size, 36))
            }
        }
    }
}
