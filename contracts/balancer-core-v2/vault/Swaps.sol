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
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "../lib/math/Math.sol";
import "../lib/helpers/EnumerableMap.sol";
import "../lib/helpers/InputHelpers.sol";
import "../lib/helpers/ReentrancyGuard.sol";

import "./PoolRegistry.sol";
import "./interfaces/IPoolSwapStructs.sol";
import "./interfaces/IGeneralPool.sol";
import "./interfaces/IMinimalSwapInfoPool.sol";
import "./balances/BalanceAllocation.sol";

abstract contract Swaps is ReentrancyGuard, PoolRegistry {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;

    using Math for int256;
    using SafeCast for uint256;
    using BalanceAllocation for bytes32;

    // Despite the external API having two separate functions for given in and given out, internally their are handled
    // together to avoid unnecessary code duplication. This enum indicates which kind of swap we're processing.

    // We use inline assembly to convert arrays of different struct types that have the same underlying data
    // representation. This doesn't trigger any actual conversions or runtime analysis: it is just coercing the type
    // system to reinterpret the data as another type.

    /**
     * @dev Converts an array of `SwapIn` into an array of `SwapRequest`, with no runtime cost.
     */

    function _toInternalSwap(SwapIn[] memory swapsIn)
        private
        pure
        returns (SwapRequest[] memory internalSwapRequests)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            internalSwapRequests := swapsIn
        }
    }

    /**
     * @dev Converts an array of `SwapOut` into an array of `InternalSwap`, with no runtime cost.
     */
    function _toInternalSwap(SwapOut[] memory swapsOut)
        private
        pure
        returns (SwapRequest[] memory internalSwapRequests)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            internalSwapRequests := swapsOut
        }
    }

    // This struct is identical in layout to SwapRequestGivenIn and SwapRequestGivenOut from IPoolSwapStructs, except
    // the 'amountIn/Out' is named 'amount'.
    struct InternalSwapRequest {
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
     * @dev Converts an InternalSwapRequest into a SwapRequestGivenIn, with no runtime cost.
     */
    function _toSwapRequestGivenIn(
        InternalSwapRequest memory internalSwapRequest
    )
        private
        pure
        returns (IPoolSwapStructs.SwapRequestGivenIn memory swapRequestGivenIn)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            swapRequestGivenIn := internalSwapRequest
        }
    }

    /**
     * @dev Converts an InternalSwapRequest into a SwapRequestGivenOut, with no runtime cost.
     */
    function _toSwapRequestGivenOut(
        InternalSwapRequest memory internalSwapRequest
    )
        private
        pure
        returns (
            IPoolSwapStructs.SwapRequestGivenOut memory swapRequestGivenOut
        )
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            swapRequestGivenOut := internalSwapRequest
        }
    }

    function batchSwapGivenIn(
        SwapIn[] memory swaps,
        IERC20[] memory tokens,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    )
        external
        override
        nonReentrant
        authenticateFor(funds.sender)
        returns (int256[] memory)
    {
        return
            _batchSwap(
                _toInternalSwap(swaps),
                tokens,
                funds,
                limits,
                deadline,
                SwapKind.GIVEN_IN
            );
    }

    function batchSwapGivenOut(
        SwapOut[] memory swaps,
        IERC20[] memory tokens,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    )
        external
        override
        nonReentrant
        authenticateFor(funds.sender)
        returns (int256[] memory)
    {
        return
            _batchSwap(
                _toInternalSwap(swaps),
                tokens,
                funds,
                limits,
                deadline,
                SwapKind.GIVEN_OUT
            );
    }

    /**
     * @dev Implements both `batchSwapGivenIn` and `batchSwapGivenIn`, depending on the `kind` value.
     */
    function _batchSwap(
        SwapRequest[] memory swaps,
        IERC20[] memory tokens,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline,
        SwapKind kind
    ) private returns (int256[] memory tokenDeltas) {
        // The deadline is timestamp-based: it should not be relied on having sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= deadline, "SWAP_DEADLINE");

        InputHelpers.ensureInputLengthMatch(tokens.length, limits.length);

        // Perform the swaps, updating the Pool token balances and computing the net Vault token deltas.
        tokenDeltas = _swapWithPools(swaps, tokens, funds, kind);

        // Process token deltas, by either transferring tokens from the sender (for positive deltas) or to the recipient
        // (for negative deltas).
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            int256 delta = tokenDeltas[i];

            require(delta <= limits[i], "SWAP_LIMIT");

            // Ignore zeroed deltas
            if (delta > 0) {
                _receiveTokens(
                    token,
                    uint256(delta),
                    funds.sender,
                    funds.fromInternalBalance
                );
            } else if (delta < 0) {
                uint256 toSend = uint256(-delta);

                if (funds.toInternalBalance) {
                    _increaseInternalBalance(funds.recipient, token, toSend);
                } else {
                    // Note protocol withdraw fees are not charged in this transfer
                    token.safeTransfer(funds.recipient, toSend);
                }
            }
        }
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

    // This struct helps implement the multihop logic: if the amount given is not provided for a swap, then the given
    // token must match the previous calculated token, and the previous calculated amount becomes the new given amount.
    // For swaps of kind given in, amount in and token in are given, while amount out and token out are calculated.
    // For swaps of kind given out, amount out and token out are given, while amount in and token in are calculated.
    struct LastSwapData {
        IERC20 tokenCalculated;
        uint256 amountCalculated;
    }

    /**
     * @dev Performs all `swaps`, calling swap hooks on the Pool contracts and updating their balances. Does not cause
     * any transfer of tokens - it instead returns the net Vault token deltas: positive if the Vault should receive
     * tokens, and negative if it should send them.
     */
    function _swapWithPools(
        SwapRequest[] memory swaps,
        IERC20[] memory tokens,
        FundManagement memory funds,
        SwapKind kind
    ) private returns (int256[] memory tokenDeltas) {
        tokenDeltas = new int256[](tokens.length);

        // Passed to _swapWithPool, which stores data about the previous swap here to implement multihop logic across
        // swaps.
        LastSwapData memory previous;

        // This variable could be declared inside the loop, but that causes the compiler to allocate memory on each loop
        // iteration, increasing gas costs.
        SwapRequest memory swap;
        for (uint256 i = 0; i < swaps.length; ++i) {
            swap = swaps[i];
            require(
                swap.tokenInIndex < tokens.length &&
                    swap.tokenOutIndex < tokens.length,
                "OUT_OF_BOUNDS"
            );

            IERC20 tokenIn = tokens[swap.tokenInIndex];
            IERC20 tokenOut = tokens[swap.tokenOutIndex];
            require(tokenIn != tokenOut, "CANNOT_SWAP_SAME_TOKEN");

            // Sentinel value for multihop logic
            if (swap.amount == 0) {
                // When the amount given is zero, we use the calculated amount for the previous swap, as long as the
                // current swap's given token is the previous' calculated token. This makes it possible to e.g. swap a
                // given amount of token A for token B, and then use the resulting token B amount to swap for token C.
                if (swaps.length > 1) {
                    bool usingPreviousToken = previous.tokenCalculated ==
                        _tokenGiven(kind, tokenIn, tokenOut);
                    require(usingPreviousToken, "MALCONSTRUCTED_MULTIHOP_SWAP");
                    swap.amount = previous.amountCalculated;
                } else {
                    revert("UNKNOWN_AMOUNT_IN_FIRST_SWAP");
                }
            }

            (uint256 amountIn, uint256 amountOut) = _swapWithPool(
                tokenIn,
                tokenOut,
                swap,
                funds.sender,
                funds.recipient,
                previous,
                kind
            );

            // Accumulate Vault deltas across swaps
            tokenDeltas[swap.tokenInIndex] = tokenDeltas[swap.tokenInIndex].add(
                amountIn.toInt256()
            );
            tokenDeltas[swap.tokenOutIndex] = tokenDeltas[swap.tokenOutIndex]
                .sub(amountOut.toInt256());

            emit Swap(swap.poolId, tokenIn, tokenOut, amountIn, amountOut);
        }
    }

    /**
     * @dev Performs `swap`, calling the Pool's contract hook and updating the Pool balance. Returns a pair with the
     * amount of tokens going into and out of the Vault as a result of this swap.
     *
     * This function expects to be called with the `previous` swap struct, which will be updated internally to
     * implement multihop logic.
     */
    function _swapWithPool(
        IERC20 tokenIn,
        IERC20 tokenOut,
        SwapRequest memory swap,
        address from,
        address to,
        LastSwapData memory previous,
        SwapKind kind
    ) private returns (uint256 amountIn, uint256 amountOut) {
        InternalSwapRequest memory request = InternalSwapRequest({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amount: swap.amount,
            poolId: swap.poolId,
            latestBlockNumberUsed: 0, // will be updated later on based on the pool specialization
            from: from,
            to: to,
            userData: swap.userData
        });

        // Get the calculated amount from the Pool and update its balances
        uint256 amountCalculated = _processSwapRequest(request, kind);

        // Store swap information for next swap
        previous.tokenCalculated = _tokenCalculated(kind, tokenIn, tokenOut);
        previous.amountCalculated = amountCalculated;

        (amountIn, amountOut) = _getAmounts(
            kind,
            swap.amount,
            amountCalculated
        );
    }

    /**
     * @dev Calls the swap hook on the Pool and updates its balances as a result of the swap being executed. The
     * interface used for the call will depend on the Pool's specialization setting.
     *
     * Returns the token amount calculated by the Pool.
     */
    function _processSwapRequest(
        InternalSwapRequest memory request,
        SwapKind kind
    ) private returns (uint256) {
        address pool = _getPoolAddress(request.poolId);
        PoolSpecialization specialization = _getPoolSpecialization(
            request.poolId
        );

        if (specialization == PoolSpecialization.MINIMAL_SWAP_INFO) {
            return
                _processMinimalSwapInfoPoolSwapRequest(
                    request,
                    IMinimalSwapInfoPool(pool),
                    kind
                );
        } else if (specialization == PoolSpecialization.TWO_TOKEN) {
            return
                _processTwoTokenPoolSwapRequest(
                    request,
                    IMinimalSwapInfoPool(pool),
                    kind
                );
        } else {
            return
                _processGeneralPoolSwapRequest(
                    request,
                    IGeneralPool(pool),
                    kind
                );
        }
    }

    function _processTwoTokenPoolSwapRequest(
        InternalSwapRequest memory request,
        IMinimalSwapInfoPool pool,
        SwapKind kind
    ) private returns (uint256 amountCalculated) {
        // Due to gas efficiency reasons, this function uses low-level knowledge of how Two Token Pool balances are
        // stored internally, instead of using getters and setters for all operations.

        (
            bytes32 tokenABalance,
            bytes32 tokenBBalance,
            TwoTokenPoolBalances storage poolBalances
        ) = _getTwoTokenPoolSharedBalances(
            request.poolId,
            request.tokenIn,
            request.tokenOut
        );

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
        (
            tokenInBalance,
            tokenOutBalance,
            amountCalculated
        ) = _callMinimalSwapInfoPoolOnSwapHook(
            request,
            pool,
            kind,
            tokenInBalance,
            tokenOutBalance
        );

        // We check the token ordering again to create the new shared cash packed struct
        poolBalances.sharedCash = request.tokenIn < request.tokenOut
            ? BalanceAllocation.toSharedCash(tokenInBalance, tokenOutBalance) // in is A, out is B
            : BalanceAllocation.toSharedCash(tokenOutBalance, tokenInBalance); // in is B, out is A
    }

    function _processMinimalSwapInfoPoolSwapRequest(
        InternalSwapRequest memory request,
        IMinimalSwapInfoPool pool,
        SwapKind kind
    ) private returns (uint256 amountCalculated) {
        bytes32 tokenInBalance = _getMinimalSwapInfoPoolBalance(
            request.poolId,
            request.tokenIn
        );
        bytes32 tokenOutBalance = _getMinimalSwapInfoPoolBalance(
            request.poolId,
            request.tokenOut
        );

        // Perform the swap request and compute the new balances for token in and token out after the swap
        (
            tokenInBalance,
            tokenOutBalance,
            amountCalculated
        ) = _callMinimalSwapInfoPoolOnSwapHook(
            request,
            pool,
            kind,
            tokenInBalance,
            tokenOutBalance
        );

        _minimalSwapInfoPoolsBalances[request.poolId][request
            .tokenIn] = tokenInBalance;
        _minimalSwapInfoPoolsBalances[request.poolId][request
            .tokenOut] = tokenOutBalance;
    }

    /**
     * @dev Calls the onSwap hook for a Pool that implements IMinimalSwapInfoPool, which are both minimal swap info
     * pools and two token pools.
     */
    function _callMinimalSwapInfoPoolOnSwapHook(
        InternalSwapRequest memory request,
        IMinimalSwapInfoPool pool,
        SwapKind kind,
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
        request.latestBlockNumberUsed = Math.max(
            tokenInBalance.blockNumber(),
            tokenOutBalance.blockNumber()
        );

        // Perform the swap request callback and compute the new balances for token in and token out after the swap
        if (kind == SwapKind.GIVEN_IN) {

                IPoolSwapStructs.SwapRequestGivenIn memory swapIn
             = _toSwapRequestGivenIn(request);
            uint256 amountOut = pool.onSwapGivenIn(
                swapIn,
                tokenInTotal,
                tokenOutTotal
            );

            newTokenInBalance = tokenInBalance.increaseCash(request.amount);
            newTokenOutBalance = tokenOutBalance.decreaseCash(amountOut);
            amountCalculated = amountOut;
        } else {

                IPoolSwapStructs.SwapRequestGivenOut memory swapOut
             = _toSwapRequestGivenOut(request);
            uint256 amountIn = pool.onSwapGivenOut(
                swapOut,
                tokenInTotal,
                tokenOutTotal
            );

            newTokenInBalance = tokenInBalance.increaseCash(amountIn);
            newTokenOutBalance = tokenOutBalance.decreaseCash(request.amount);
            amountCalculated = amountIn;
        }
    }

    function _processGeneralPoolSwapRequest(
        InternalSwapRequest memory request,
        IGeneralPool pool,
        SwapKind kind
    ) private returns (uint256 amountCalculated) {
        bytes32 tokenInBalance;
        bytes32 tokenOutBalance;


            EnumerableMap.IERC20ToBytes32Map storage poolBalances
         = _generalPoolsBalances[request.poolId];
        uint256 indexIn = poolBalances.indexOf(
            request.tokenIn,
            "TOKEN_NOT_REGISTERED"
        );
        uint256 indexOut = poolBalances.indexOf(
            request.tokenOut,
            "TOKEN_NOT_REGISTERED"
        );

        uint256 tokenAmount = poolBalances.length();
        uint256[] memory currentBalances = new uint256[](tokenAmount);

        for (uint256 i = 0; i < tokenAmount; i++) {
            // Because the iteration is bounded by `tokenAmount` and no tokens are registered or deregistered here, we
            // can use `unchecked_valueAt` as we know `i` is a valid token index, saving storage reads.
            bytes32 balance = poolBalances.unchecked_valueAt(i);

            currentBalances[i] = balance.total();
            request.latestBlockNumberUsed = Math.max(
                request.latestBlockNumberUsed,
                balance.blockNumber()
            );

            if (i == indexIn) {
                tokenInBalance = balance;
            } else if (i == indexOut) {
                tokenOutBalance = balance;
            }
        }

        // Perform the swap request callback and compute the new balances for token in and token out after the swap
        if (kind == SwapKind.GIVEN_IN) {

                IPoolSwapStructs.SwapRequestGivenIn memory swapRequestIn
             = _toSwapRequestGivenIn(request);
            uint256 amountOut = pool.onSwapGivenIn(
                swapRequestIn,
                currentBalances,
                indexIn,
                indexOut
            );

            amountCalculated = amountOut;
            tokenInBalance = tokenInBalance.increaseCash(request.amount);
            tokenOutBalance = tokenOutBalance.decreaseCash(amountOut);
        } else {

                IPoolSwapStructs.SwapRequestGivenOut memory swapRequestOut
             = _toSwapRequestGivenOut(request);
            uint256 amountIn = pool.onSwapGivenOut(
                swapRequestOut,
                currentBalances,
                indexIn,
                indexOut
            );

            amountCalculated = amountIn;
            tokenInBalance = tokenInBalance.increaseCash(amountIn);
            tokenOutBalance = tokenOutBalance.decreaseCash(request.amount);
        }

        // Because no token registrations or unregistrations happened between now and when we retrieved the indexes for
        // token in and token out, we can use `unchecked_setAt`, saving storage reads.
        poolBalances.unchecked_setAt(indexIn, tokenInBalance);
        poolBalances.unchecked_setAt(indexOut, tokenOutBalance);
    }

    // This function is not marked as `nonReentrant` because the underlying mechanism relies on reentrancy
    function queryBatchSwap(
        SwapKind kind,
        SwapRequest[] memory swaps,
        IERC20[] memory tokens,
        FundManagement memory funds
    ) external override returns (int256[] memory) {
        // In order to accurately 'simulate' swaps, this function actually does perform the swaps, including calling the
        // Pool hooks and updating  balances in storage. However, once it computes the final Vault Deltas it then
        // reverts unconditionally, returning this array as the revert data.
        // By wrapping this reverting call, we can decode the deltas 'returned' and return them as a normal Solidity
        // function would. The only caveat is the function becomes non-view, but off-chain clients can still call it
        // via eth_call to get the expected result.
        //
        // This technique was inspired by the work from the Gnosis team in the Gnosis Safe contract:
        // https://github.com/gnosis/safe-contracts/blob/v1.2.0/contracts/GnosisSafe.sol#L265

        // Most of this function is implemented using inline assembly, as the actual work it needs to do is not
        // significant, and Solidity is not particularly well-suited to generate this behavior, resulting in a large
        // amount of generated bytecode.

        if (msg.sender != address(this)) {
            // We perform an external call to ourselves, forwarding the same calldata.

            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = address(this).call(msg.data);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // This call should always revert to decode the actual token deltas from the revert reason
                switch success
                    case 0 {
                        // The returndata now contains the raw memory representation of an array: length + data. We need
                        // to return an ABI-encoded representation of this array, which we manually create at address 0
                        // in memory. We can safely overwrite whatever is stored there as we take full control of the
                        // execution and then immediately return.

                        // An ABI-encoded array contains an additional field when compared to its raw memory
                        // representation: an offset to the location of the length. The offset itself is 32 bytes long,
                        // so the smallest value we can use is 32 for the data to be located immediately after it.
                        mstore(0, 32)

                        // We nnow copy the raw memory array from returndata into memory. Since the offset takes up 32
                        // bytes, we start copying at address 0x20.
                        returndatacopy(0x20, 0, returndatasize())

                        // We finally return the ABI-encoded array, which has a total length equal to that of the array
                        // (returndata), plus the 32 bytes for the offset.
                        return(0, add(returndatasize(), 32))
                    }
                    default {
                        // This call should always revert, but we fail nonetheless if that didn't happen
                        invalid()
                    }
            }
        } else {
            int256[] memory deltas = _swapWithPools(swaps, tokens, funds, kind);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // We will return a raw representation of the array in memory, which is composed of a 32 byte length,
                // followed by the 32 byte int256 values. Because revert expects a size in bytes, we multiply the array
                // length (stored at `deltas`) by 32.
                let size := mul(mload(deltas), 32)

                // When copying from `deltas` into returndata, we copy an additional 32 bytes to also return the array's
                // length.
                revert(deltas, add(size, 32))
            }
        }
    }
}
