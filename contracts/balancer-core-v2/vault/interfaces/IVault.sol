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

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IAuthorizer.sol";
import "./IFlashLoanReceiver.sol";
import "./IAsset.sol";
import "./IWETH.sol";
import "../ProtocolFeesCollector.sol";

pragma solidity ^0.7.0;

/**
 * @dev Full external interface for the Vault core contract - no external or public methods exist in the contract that
 * don't override one of these declarations.
 */
interface IVault {
    // Generalities about the Vault:
    //
    // - Whenever documentation refers to 'tokens', it strictly refers to ERC20-compliant token contracts. Tokens are
    // transferred out of the Vault by calling the `IERC20.transfer` function, and transferred in by calling
    // `IERC20.transferFrom`. In these cases, the sender must have previously allowed the Vault to use their tokens by
    // calling `IERC20.approve`. The only deviation from the ERC20 standard that is supported is functions not returning
    // a boolean value: in these scenarios, a non-reverting call is assumed to be successful.
    //
    // - All non-view functions in the Vault are non-reentrant: calling them while another one is mid-execution (e.g.
    // while execution control is transferred to a token contract during a swap) will result in a revert. View
    // functions can be called in a re-reentrant way, but doing so might cause them to return inconsistent results.
    // Contracts calling view functions in the Vault must make sure the Vault has not already been entered.
    //
    // - View functions revert if referring to either unregistered Pools, or unregistered tokens for registered Pools.

    // Authorizer
    //
    // Some system actions are permissioned, like setting and collecting protocol fees. This permissioning system exists
    // outside of the Vault in the Authorizer contract: the Vault simply calls the Authorizer to check if the caller
    // can perform a given action.
    // The only exceptions to this involve relayers. A relayer is an account (typically a contract) that can use the
    // Internal Balance and Vault allowance of other accounts. For an account to be able to wield this power,
    // two things must occur:
    //  - The Authorizer must allow the the relayer to call the functions associated with this permission.
    //    In other words, Balancer governance must specifically approve the functions each relayer can call
    //  - Each user must approve the relayer to act on their behalf
    // This double protection means users cannot be tricked into allowing malicious relayers (because they will not
    // have been allowed by the Authorizer), nor can malicious relayers approved by a compromised Authorizer drain
    // user funds, since they would also need to be approved by each individual user.

    /**
     * @dev Returns the Vault's WETH instance.
     */
    // solhint-disable-next-line func-name-mixedcase
    function WETH() external view returns (IWETH);

    /**
     * @dev Returns the Vault's Authorizer.
     */
    function getAuthorizer() external view returns (IAuthorizer);

    /**
     * @dev Sets a new Authorizer for the Vault. The caller must be allowed by the current Authorizer to do this.
     */
    function changeAuthorizer(IAuthorizer newAuthorizer) external;

    /**
     * @dev Returns true if `user` has allowed `relayer` to act as a relayer for them.
     */
    function hasAllowedRelayer(address user, address relayer) external view returns (bool);

    /**
     * @dev Allows `relayer` to act as a relayer for the caller if `allowed` is true, and disallows it otherwise.
     */
    function changeRelayerAllowance(address relayer, bool allowed) external;

    // Internal Balance
    //
    // Users can deposit tokens into the Vault, where they are allocated to their Internal Balance.
    // This Internal Balance can be withdrawn or transferred, and it can also be used when joining Pools or
    // performing swaps, with greatly reduced gas costs. Swaps and Pool exits can also deposit to
    // Internal Balance.
    //
    // Internal Balance functions feature batching, which means each call can be used to perform multiple operations of
    // the same kind (deposit, withdraw or transfer) at once.

    /**
     * @dev Data for Internal Balance deposits and withdrawals, which include the possibility for ETH to be sent and
     * received without manual WETH wrapping or unwrapping.
     */
    struct AssetBalanceTransfer {
        IAsset asset;
        uint256 amount;
        address sender;
        address payable recipient;
    }

    /**
     * @dev Data for Internal Balance transfers, which are limited to ERC20 tokens.
     */
    struct TokenBalanceTransfer {
        IERC20 token;
        uint256 amount;
        address sender;
        address payable recipient;
    }

    /**
     * @dev Returns `user`'s Internal Balance for a set of tokens.
     */
    function getInternalBalance(address user, IERC20[] memory tokens) external view returns (uint256[] memory);

    /**
     * @dev Deposits `amount` assets from each `sender` address into Internal Balances of the corresponding `recipient`
     * accounts. The senders must have allowed the Vault to use their tokens via `IERC20.approve()`.
     *
     * For each deposit, if the caller is not `sender`, it must be an authorized relayer for them.
     *
     * ETH can be used by passing the ETH sentinel value as the asset and forwarding ETH in the call. It will be
     * wrapped into WETH and deposited as that token. Any ETH amount remaining will be sent back to the caller (not the
     * sender, which is relevant for relayers).
     *
     * Reverts if ETH was forwarded but not used in any transfer.
     */
    function depositToInternalBalance(AssetBalanceTransfer[] memory transfers) external payable;

    /**
     * @dev Withdraws `amount` assets from each `sender` address' Internal Balance to the corresponding `recipient`
     * accounts. The senders must have allowed the Vault to use their tokens via `IERC20.approve()`.
     *
     * For each withdrawal, if the caller is not `sender`, it must be an authorized relayer for them.
     *
     * ETH can be used by passing the ETH sentinel value as the asset. This will deduct WETH instead, unwrap it and send
     * it to the recipient.
     */
    function withdrawFromInternalBalance(AssetBalanceTransfer[] memory transfers) external;

    /**
     * @dev Transfers tokens from the internal balances of each `sender` address to the Internal Balances of each
     * `recipient`.
     *
     * For each transfer, if the caller is not `sender`, it must be an authorized relayer for them.
     */
    function transferInternalBalance(TokenBalanceTransfer[] memory transfers) external;

    /**
     * @dev Transfers tokens from each `sender` address to the corresponding `recipient` account, making use of the
     * Vault's allowance. This action is equivalent to an Internal Balance deposit followed immediately by a withdrawal.
     *
     * For each transfer, if the caller is not `sender`, it must be an authorized relayer for them.
     *
     * Typically, this function will only be called by relayers, letting them leverage the allowance users have already
     * given to the Vault.
     */
    function transferToExternalBalance(TokenBalanceTransfer[] memory transfers) external;

    /**
     * @dev Emitted when a user's Internal Balance changes, due to calls on the Internal Balance functions, or
     * to interacting with Pools using Internal Balance.
     *
     * Because Internal Balance works exclusively with ERC20 tokens, ETH deposits and withdrawals will use
     * the WETH address.
     */
    event InternalBalanceChanged(address indexed user, IERC20 indexed token, int256 delta);

    // Pools
    //
    // There are three specialization settings for Pools, which allow for lower gas cost swaps, at the cost of reduced
    // functionality:
    //
    //  - general: no specialization, suited for all Pools. IGeneralPool is used for swap request callbacks, passing the
    // balance of all tokens in the Pool. These Pools have the largest swap costs (because of the extra storage reads),
    // and these increase with the number of registered tokens.
    //
    //  - minimal swap info: IMinimalSwapInfoPool is used instead of IGeneralPool, which saves gas by only passing the
    // balance of the two tokens involved in the swap. This is suitable for some pricing algorithms, like the weighted
    // constant product one popularized by Balancer V1. Swap costs are smaller compared to general Pools, and are
    // independent of the number of registered tokens.
    //
    //  - two tokens: only allows two tokens to be registered. This achieves the lowest possible swap gas cost. Like
    // minimal swap info Pools, these are called via IMinimalSwapInfoPool.

    enum PoolSpecialization { GENERAL, MINIMAL_SWAP_INFO, TWO_TOKEN }

    /**
     * @dev Registers the caller contract as a Pool with a chosen specialization setting. Returns the Pool's ID,
     * which is used in all Pool-related functions. Pools cannot be deregistered, nor can the Pool's specialization
     * be changed.
     *
     * The caller is expected to be a smart contract that implements one of `IGeneralPool` or `IMinimalSwapInfoPool`.
     * This contract is known as the Pool's contract. Note that the same caller may register itself as multiple Pools
     * with unique Pool IDs, or in other words, multiple Pools may have the same contract.
     *
     * Emits a `PoolRegistered` event.
     */
    function registerPool(PoolSpecialization specialization) external returns (bytes32);

    /**
     * @dev Emitted when a Pool is registered by calling `registerPool`.
     */
    event PoolRegistered(bytes32 poolId);

    /**
     * @dev Returns a Pool's contract address and specialization setting.
     */
    function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);

    /**
     * @dev Registers `tokens` for the `poolId` Pool. Must be called by the Pool's contract.
     *
     * Pools can only interact with tokens they have registered. Users join a Pool by transferring registered tokens,
     * exit by receiving registered tokens, and can only swap registered tokens.
     *
     * Each token can only be registered once. For Pools with the Two Token specialization, `tokens` must have a length
     * of two, that is, both tokens must be registered in the same `registerTokens` call.
     *
     * The `tokens` and `assetManagers` arrays must have the same length, and each entry in these indicates the Asset
     * Manager for each token. Asset Managers can manage a Pool's tokens by withdrawing and depositing them directly
     * (via `managePoolBalance` with the appropriate AssetManagerOpKind setting), and even set them to arbitrary amounts
     * with the UPDATE OpKind. They are therefore expected to be highly secured smart contracts with sound design
     * principles, and the decision to add an Asset Manager should not be made lightly.
     *
     * Pools can choose not to assign an Asset Manager to a given token by passing in the zero address. However, once an
     * Asset Manager is set, it cannot be changed except by deregistering the associated token and registering again
     * with a different Asset Manager.
     *
     * Emits `TokensRegistered` events.
     */
    function registerTokens(
        bytes32 poolId,
        IERC20[] calldata tokens,
        address[] calldata assetManagers
    ) external;

    /**
     * @dev Emitted when a Pool registers tokens by calling `registerTokens`.
     */
    event TokensRegistered(bytes32 poolId, IERC20[] tokens, address[] assetManagers);

    /**
     * @dev Deregisters `tokens` for the `poolId` Pool. Must be called by the Pool's contract.
     *
     * Only registered tokens (via `registerTokens`) can be deregistered. Additionally, they must have zero total
     * balance. For Pools with the Two Token specialization, `tokens` must have a length of two, that is, both tokens
     * must be deregistered in the same `deregisterTokens` call.
     *
     * A deregistered token can be re-registered later on, possibly with a different Asset Manager.
     *
     * Emits a `TokensDeregistered` event.
     */
    function deregisterTokens(bytes32 poolId, IERC20[] calldata tokens) external;

    /**
     * @dev Emitted when a Pool deregisters tokens by calling `deregisterTokens`.
     */
    event TokensDeregistered(bytes32 poolId, IERC20[] tokens);

    /**
     * @dev Returns a Pool's registered tokens, and the total balance for each.
     *
     * The order of the `tokens` array is the same order that will be used in `joinPool`, `exitPool`, as well as in all
     * Pool hooks (where applicable). Calls to `registerTokens` and `deregisterTokens` may change this order.
     *
     * If a Pool only registers tokens once, and these are sorted in ascending order, they will be stored in the same
     * order as passed to `registerTokens`.
     *
     * Total balances include both tokens held by the Vault and those withdrawn by the Pool's Asset Managers. These are
     * the amounts used by joins, exits and swaps.
     */
    function getPoolTokens(bytes32 poolId) external view returns (IERC20[] memory tokens, uint256[] memory balances);

    /**
     * @dev Returns detailed information for a Pool's registered token.
     *
     * `cash` is the number of tokens the Vault currently holds for the Pool. `managed` is the number of tokens
     * withdrawn and held outside the Vault by the Pool's token Asset Manager. The Pool's total balance for `token`
     * equals the sum of `cash` and `managed`.
     *
     * `blockNumber` is the number of the block in which `token`'s balance was last modified (via either a join, exit,
     * swap, or Asset Management interaction). This value is useful to avoid so-called 'sandwich attacks', for example
     * when developing price oracles.
     *
     * `assetManager` is the Pool's token Asset Manager.
     */
    function getPoolTokenInfo(bytes32 poolId, IERC20 token)
        external
        view
        returns (
            uint256 cash,
            uint256 managed,
            uint256 blockNumber,
            address assetManager
        );

    struct PoolBalanceChange {
        IAsset[] assets;
        uint256[] limits;
        bytes userData;
        bool useInternalBalance;
    }

    /**
     * @dev Called by users to join a Pool, which transfers tokens from `sender` into the Pool's balance. This will
     * trigger custom Pool behavior, which will typically grant something in return to `recipient` - often tokenized
     * Pool shares.
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * The `assets` and `maxAmountsIn` arrays must have the same length, and each entry indicates the maximum amount
     * to send for each asset. The amounts to send are decided by the Pool and not the Vault: it just enforces
     * these maximums.
     *
     * If joining a Pool that holds WETH, it is possible to send ETH directly: the Vault will do the wrapping. To enable
     * this mechanism, the IAsset sentinel value (the zero address) must be passed in the `assets` array instead of the
     * WETH address. Note that it is not possible to combine ETH and WETH in the same join. Any excess ETH will be sent
     * back to the caller (not the sender, which is important for relayers).
     *
     * `assets` must have the same length and order as the array returned by `getPoolTokens`. This prevents issues when
     * interacting with Pools that register and deregister tokens frequently. If sending ETH however, the array must be
     * sorted *before* replacing the WETH address with the ETH address, which means the final `assets` array might not
     * be sorted.
     *
     * If `fromInternalBalance` is true, the caller's Internal Balance will be preferred: ERC20 transfers will only
     * be made for the difference between the requested amount and Internal Balance (if any). Note that ETH cannot be
     * withdrawn from Internal Balance: attempting to do so will trigger a revert.
     *
     * This causes the Vault to call the `IBasePool.onJoinPool` hook on the Pool's contract, where Pools implement
     * their own custom logic. This typically requires additional information from the user (such as the expected number
     * of Pool shares). This can be encoded in the `userData` argument, which is ignored by the Vault and passed
     * directly to the Pool's contract, as is `recipient`.
     *
     * Emits a `PoolBalanceChanged` event.
     */
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    /**
     * @dev Called by users to exit a Pool, which transfers tokens from the Pool's balance to `recipient`. This will
     * trigger custom Pool behavior, which will typically ask for something in return from `sender` - often tokenized
     * Pool shares. The amount of tokens that can be withdrawn is limited by the Pool's `cash` balance (see
     * `getPoolTokenInfo`).
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * The `tokens` and `minAmountsOut` arrays must have the same length, and each entry in these indicates the minimum
     * token amount to receive for each token contract. The amounts to send are decided by the Pool and not the Vault:
     * it just enforces these minimums.
     *
     * If exiting a Pool that holds WETH, it is possible to receive ETH directly: the Vault will do the unwrapping. To
     * enable this mechanism, the IAsset sentinel value (the zero address) must be passed in the `assets` array instead
     * of the WETH address. Note that it is not possible to combine ETH and WETH in the same exit.
     *
     * `assets` must have the same length and order as the array returned by `getPoolTokens`. This prevents issues when
     * interacting with Pools that register and deregister tokens frequently. If receiving ETH however, the array must
     * be sorted *before* replacing the WETH address with the ETH address, which means the final `assets` array might
     * not be sorted.
     *
     * If `toInternalBalance` is true, the tokens will be deposited to `recipient`'s Internal Balance. Otherwise,
     * an ERC20 transfer will be performed. Note that ETH cannot be deposited to Internal Balance: attempting to
     * do so will trigger a revert.
     *
     * `minAmountsOut` is the minimum amount of tokens the user expects to get out of the Pool, for each token in the
     * `tokens` array. This array must match the Pool's registered tokens.
     *
     * Pools are free to implement any arbitrary logic in the `IPool.onExitPool` hook, and may require additional
     * information (such as the number of Pool shares to provide). This can be encoded in the `userData` argument, which
     * is ignored by the Vault and passed directly to the Pool.
     *
     * This causes the Vault to call the `IBasePool.onExitPool` hook on the Pool's contract, where Pools implement
     * their own custom logic. This typically requires additional information from the user (such as the expected number
     * of Pool shares to return). This can be encoded in the `userData` argument, which is ignored by the Vault and
     * passed directly to the Pool's contract.
     *
     * Emits a `PoolBalanceChanged` event.
     */
    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external;

    struct ExitPoolRequest {
        IAsset[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    /**
     * @dev Emitted when a user joins or exits a Pool by calling `joinPool` or `exitPool` respectively.
     */
    event PoolBalanceChanged(
        bytes32 indexed poolId,
        address indexed liquidityProvider,
        IERC20[] tokens,
        int256[] amounts,
        uint256[] protocolFees
    );

    enum PoolBalanceChangeKind { JOIN, EXIT }

    // Swaps
    //
    // Users can swap tokens with Pools by calling the `batchSwapGivenIn` and `batchSwapGivenOut` functions. To do this,
    // they need not trust Pool contracts in any way: all security checks are made by the Vault. They must however be
    // aware of the Pools' pricing algorithms in order to estimate the prices Pools will quote.
    //
    // Both swap functions are batched, meaning they perform multiple swaps in sequence. In each individual swap,
    // tokens of one kind are sent from the sender to the Pool (this is the 'token in'), and tokens of another
    // kind are sent from the Pool to the sender in exchange (this is the 'token out'). More complex swaps, such
    // as one token in to multiple tokens out can be achieved by batching together individual swaps.
    //
    // Additionally, it is possible to chain swaps by using the output of one as the input to the next, as
    // well as the opposite. This extended swap is known as a 'multihop' swap, since it 'hops' through a number of
    // intermediate tokens before arriving at the final intended token.
    //
    // In all cases, tokens are only transferred in and out of the Vault (or withdrawn from and deposited into Internal
    // Balance) after all individual swaps have been completed, and the net token balance change computed. This makes
    // certain swap patterns, such as multihops, or swaps that interact with the same token pair in multiple Pools, cost
    // much less gas than they would otherwise.
    //
    // It also means that under certain conditions it is possible to perform arbitrage by swapping with multiple
    // Pools in a way that results in net token movement out of the Vault (profit), with no tokens being sent in (only
    // updating the Pool's internal accounting).
    //
    // To protect users from front-running or the market changing rapidly, they supply a list of 'limits' for each token
    // involved in the swap, where either the maximum number of tokens to send (by passing a positive value) or the
    // minimum amount of tokens to receive (by passing a negative value) is specified.
    //
    // Additionally, a 'deadline' timestamp can also be provided, forcing the swap to fail if it occurs after
    // this point in time (e.g. if the transaction failed to be included in a block promptly).
    //
    // If interacting with Pools that hold WETH, it is possible to both send and receive ETH directly: the Vault will do
    // the wrapping and unwrapping. To enable this mechanism, the IAsset sentinel value (the zero address) must be
    // passed in the `assets` array instead of the WETH address. Note that it is possible to combine ETH and WETH in the
    // same swap. Any excess ETH will be sent back to the caller (not the sender, which is relevant for relayers).
    //
    // Finally, Internal Balance can be used when either sending or receiving tokens.

    /**
     * @dev Performs a series of swaps with one or multiple Pools. In each individual swap, the amount of tokens sent to
     * the Pool is determined by the caller. For swaps where the amount of tokens received from the Pool is
     * determined instead, see `batchSwapGivenOut`.
     *
     * Returns an array with the net Vault asset balance deltas. Positive amounts represent tokens (or ETH) sent to the
     * Vault, and negative amounts tokens (or ETH) sent by the Vault. Each delta corresponds to the asset at the same
     * index in the `assets` array.
     *
     * Swaps are executed sequentially, in the order specified by the `swaps` array. Each array element describes a
     * Pool, the token and amount to send to this Pool, and the token to receive from it (but not the amount). This will
     * be determined by the Pool's pricing algorithm once the Vault calls the `onSwapGivenIn` hook.
     *
     * Multihop swaps can be executed by passing an `amountIn` value of zero for a swap. This will cause the amount out
     * of the previous swap to be used as the amount in for the current one. In such a scenario, `tokenIn` must equal
     * the previous swap's `tokenOut`.
     *
     * The `assets` array contains the addresses of all assets involved in the swaps. These are either token addresses,
     * or the IAsset sentinel value (the zero address) for ETH. Each entry in the `swaps` array specifies tokens in and
     * out by referencing an index in `assets`. Note that Pools never interact with ETH directly: it will be wrapped or
     * unwrapped using WETH by the Vault.
     *
     * Internal Balance usage, sender, and recipient are determined by the `funds` struct. The `limits` array specifies
     * the minimum or maximum amount of each token the vault is allowed to transfer.
     *
     * Emits `Swap` events.
     */
    function batchSwapGivenIn(
        SwapIn[] calldata swaps,
        IAsset[] memory assets,
        FundManagement calldata funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory);

    /**
     * @dev Data for each individual swap executed by `batchSwapGivenIn`. The tokens in and out are indexed in the
     * `assets` array passed to that function, where an ETH asset is translated into WETH.
     *
     * If `amountIn` is zero, the multihop mechanism is used to determine the actual amount based on the amount out from
     * the previous swap.
     *
     * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwapGivenIn` hook, and may be
     * used to extend swap behavior.
     */
    struct SwapIn {
        bytes32 poolId;
        uint256 tokenInIndex;
        uint256 tokenOutIndex;
        uint256 amountIn;
        bytes userData;
    }

    /**
     * @dev Performs a series of swaps with one or multiple Pools. In each individual swap, the amount of tokens
     * received from the Pool is determined by the caller. For swaps where the amount of tokens sent to the Pool is
     * determined instead, see `batchSwapGivenIn`.
     *
     * Returns an array with the net Vault asset balance deltas. Positive amounts represent tokens (or ETH) sent to the
     * Vault, and negative amounts tokens (or ETH) sent by the Vault. Each delta corresponds to the asset at the same
     * index in the `assets` array.
     *
     * Swaps are executed sequentially, in the order specified by the `swaps` array. Each array element describes a
     * Pool, the token and amount to receive from this Pool, and the token to send to it (but not the amount). This will
     * be determined by the Pool's pricing algorithm once the Vault calls the `onSwapGivenOut` hook.
     *
     * Multihop swaps can be executed by passing an `amountOut` value of zero for a swap. This will cause the amount in
     * of the previous swap to be used as the amount out of the current one. In such a scenario, `tokenOut` must equal
     * the previous swap's `tokenIn`.
     *
     * The `assets` array contains the addresses of all assets involved in the swaps. These are either token addresses,
     * or the IAsset sentinel value (the zero address) for ETH. Each entry in the `swaps` array specifies tokens in and
     * out by referencing an index in `assets`. Note that Pools never interact with ETH directly: it will be wrapped or
     * unwrapped using WETH by the Vault.
     *
     * Internal Balance usage and recipient are determined by the `funds` struct. The `limits` array specifies the
     * minimum amount of each token the vault must transfer.
     *
     * Emits `Swap` events.
     */
    function batchSwapGivenOut(
        SwapOut[] calldata swaps,
        IAsset[] memory assets,
        FundManagement calldata funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory);

    /**
     * @dev Data for each individual swap executed by `batchSwapGivenOut`. The tokens in and out are indexed in the
     * `assets` array passed to that function, where an ETH asset is translated into WETH.
     *
     * If `amountOut` is zero, the multihop mechanism is used to determine the actual amount based on the amount in from
     * the previous swap.
     *
     * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwapGivenOut` hook, and may be
     * used to extend swap behavior.
     */
    struct SwapOut {
        bytes32 poolId;
        uint256 tokenInIndex;
        uint256 tokenOutIndex;
        uint256 amountOut;
        bytes userData;
    }

    /**
     * @dev Performs a swap with a single Pool.
     *
     * If the swap is given in (the number of tokens to send to the Pool is known), it returns the amount of tokens
     * taken from the Pool, which must be larger or equal to `limit`.
     *
     * If the swap is given out (the number of tokens to take from the Pool is known), it returns the amount of
     * tokens sent by the Pool, which must be smaller or equal to `limit`.
     *
     * Internal Balance usage and the recipient are determined by the `funds` struct.
     *
     * Emits a `Swap` event.
     */
    function swap(
        SingleSwap memory request,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);

    /**
     * @dev Data for two-token swaps executed by `swap`. Compared to `SwapIn` and `SwapOut`, the tokens in and out
     * are given so there is no asset array, but similarly, the ETH asset is translated into WETH.
     *
     * Here `amount` refers to `amountIn` or `amountOut` depending on whether `kind` specifies a swap given in or out.
     *
     * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwap` hook, and may be
     * used to extend swap behavior.
     */
    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

    /**
     * @dev Emitted for each individual swap performed by `batchSwapGivenIn` and `batchSwapGivenOut`.
     */
    event Swap(
        bytes32 indexed poolId,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 tokensIn,
        uint256 tokensOut
    );

    /**
     * @dev All tokens in a swap are either sent from the `sender` account to the Vault, or from the Vault to the
     * `recipient` account.
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * If `fromInternalBalance` is true, the `sender`'s Internal Balance will be preferred, performing an ERC20
     * transfer for the difference between the requested amount and the User's Internal Balance (if any). The `sender`
     * must have allowed the Vault to use their tokens via `IERC20.approve()`. This matches the behavior of
     * `joinPool`.
     *
     * If `toInternalBalance` is true, tokens will be deposited to `recipient`'s internal balance instead of
     * transferred. This matches the behavior of `exitPool`.
     *
     * Note that ETH cannot be deposited to or withdrawn from Internal Balance: attempting to do so will trigger a
     * revert.
     */
    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    /**
     * @dev Simulates a call to `batchSwapGivenIn` or `batchSwapGivenOut`, returning an array of Vault asset deltas.
     * Each element in the array corresponds to the asset at the same index, and indicates the number of tokens (or ETH)
     * the Vault would take from the sender (if positive) or send to the recipient (if negative). The arguments it
     * receives are the same that an equivalent `batchSwapGivenIn` or `batchSwapGivenOut` call would receive, except the
     * `SwapRequest` struct is used instead, and the `kind` argument specifies whether the swap is given in or given
     * out.
     *
     * Unlike `batchSwapGivenIn` and `batchSwapGivenOut`, this function performs no checks on the sender or recipient
     * field in the `funds` struct. This makes it suitable to be called by off-chain applications via eth_call without
     * needing to hold tokens, approve them for the Vault, or even know a user's address.
     *
     * Note that this function is not 'view' (due to implementation details): the client code must explicitly execute
     * eth_call instead of eth_sendTransaction.
     */
    function queryBatchSwap(
        SwapKind kind,
        SwapRequest[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds
    ) external returns (int256[] memory assetDeltas);

    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    // This struct is identical in layout to SwapIn and SwapOut, except the 'amountIn/Out' field is named 'amount'.
    struct SwapRequest {
        bytes32 poolId;
        uint256 tokenInIndex;
        uint256 tokenOutIndex;
        uint256 amount;
        bytes userData;
    }

    // Flash Loans

    /**
     * @dev Performs a 'flash loan', sending tokens to `receiver` and executing the `receiveFlashLoan` hook on it,
     * and then reverting unless the tokens plus a protocol fee have been returned.
     *
     * The `tokens` and `amounts` arrays must have the same length, and each entry in these indicates the amount to
     * loan for each token contract. `tokens` must be sorted in ascending order.
     *
     * The 'receiverData' field is ignored by the Vault, and forwarded as-is to `receiver` as part of the
     * `receiveFlashLoan` call.
     */
    function flashLoan(
        IFlashLoanReceiver receiver,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata receiverData
    ) external;

    // Asset Management
    //
    // Each token registered for a Pool can be assigned an Asset Manager, which is able to freely withdraw the Pool's
    // tokens from the Vault, deposit them, or assign arbitrary values to its `managed` balance (see
    // `getPoolTokenInfo`). This makes them extremely powerful and dangerous, as they can not only steal a Pool's
    // tokens, but also manipulate its prices. However, a properly designed Asset Manager smart contract can be used
    // for the Pool's benefit, for example by lending unused tokens out for interest, or using them to participate
    // in voting protocols.
    // This concept is unrelated to the IAsset interface.

    /**
     * @dev Called by a Pool's Asset Manager to perform an operation (withdraw, deposit, or update) in the Vault.
     * Array input allows asset managers to manage multiple tokens for a pool in a single transaction.
     */
    function managePoolBalance(
        bytes32 poolId,
        AssetManagerOpKind kind,
        AssetManagerTransfer[] memory transfers
    ) external;

    struct AssetManagerTransfer {
        IERC20 token;
        uint256 amount;
    }

    /**
     * @dev Emitted when a Pool's token Asset manager withdraws or deposits token balance via `managePoolBalance`
     * (using the AssetManagerOpKind to determine the type of update)
     */
    event PoolBalanceManaged(bytes32 indexed poolId, address indexed assetManager, IERC20 indexed token, int256 amount);

    /**
     * Deposits increase the Pool's cash, but decrease its managed balance, leaving the total balance unchanged.
     *
     * Withdrawals decrease the Pool's cash, but increase its managed balance, leaving the total balance unchanged.
     *
     * Updates don't affect the Pool's cash balance, but because the managed balance changes, it does alter the total.
     * The external amount can be either increased or decreased by this call (i.e., reporting a gain or a loss).
     */
    enum AssetManagerOpKind { DEPOSIT, WITHDRAW, UPDATE }

    // Protocol Fees
    //
    // Some operations cause the Vault to collect tokens in the form of protocol fees, which can then be withdrawn by
    // permissioned accounts.
    //
    // There are two kinds of protocol fees:
    //
    //  - flash loan fees: charged on all flash loans, as a percentage of the amounts lent.
    //
    //  - swap fees: a percentage of the fees charged by Pools when performing swaps. For a number of reasons, including
    // swap gas costs and interface simplicity, protocol swap fees are not charged on each individual swap. Rather,
    // Pools are expected to keep track of how many swap fees they have charged, and pay any outstanding debts to the
    // Vault when they are joined or exited. This prevents users from joining a Pool with unpaid debt, as well as
    // exiting a Pool in debt without first paying their share.

    /**
     * @dev Returns the current protocol fee module.
     */
    function getProtocolFeesCollector() external view returns (ProtocolFeesCollector);
}
