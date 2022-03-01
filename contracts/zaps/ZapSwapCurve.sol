// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

import "../libraries/Authorizable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IVault.sol";
import "../interfaces/ICurvePool.sol";

// TODO Due to the nature of the curve contracts, there are a number of design
// decisions made in this contract which primarily aim to generalize integration
// with curve. Curve contracts have often an inconsistent interface to many
// functions in their contracts which has influenced the design of this contract
// to target curve pool functions using function signatures computed off-chain.
// The validation of this and other features of this contract stem from this
// problem, for instance, the curve pool contracts target their underlying
// tokens using fixed-length dimensional arrays of length 2 or 3. We could
// harden this contract further by utilizing the "coins" function on the curve
// contract which would enable this contract validate that our input structure
// is correct. However, this would also run into problems as the guarantee of
// consistency of the "coins" function is also in question across the suite of
// pools in the curve ecosystem. There may be a solution to mitigate this
// problem but may be more trouble than it's worth.

/// @title ZapCurveTokenToPrincipalToken
/// @notice Allows the user to buy and sell principal tokens using a wider
/// array of tokens
/// @dev This contract introduces the concept of "root tokens" which are the
/// set of constituent tokens for a given curve pool. Each principal token
/// is constructed by a yield-generating position which in this case will be
/// represented by a curve LP token. This is referred to as the "base token"
/// and in the case where the user wishes to purchase or sell a principal token,
/// it can only be done so by using this token.
///
/// What this contract intends to do is enable the user purchase or sell
/// a position using those "root tokens" which would garner significant UX
/// improvements. The flow in the case of purchasing is as follows, the root
/// tokens are added as liquidity into the correct curve pool, giving a curve
/// "LP token" or "base token". Subsequently this is then used to purchase the
/// principal token. Selling works similarly but in the reverse direction.
///
/// Ex- Alice bought (x) amount curve LP token (let's say crvLUSD token) using LUSD (root token)
/// purchased (x) amount can be used to purchase the principal token by putting that amount
/// in the wrapped position contract.
contract ZapSwapCurve is Authorizable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    // Store the accessibility state of the contract
    bool public isFrozen;

    // A constant to represent ether
    address internal constant _ETH_CONSTANT =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // Reference to the main balancer vault
    IVault internal immutable _balancer;

    /////////////////////////
    /// Zap In Data Structure
    /////////////////////////

    struct ZapInInfo {
        // The balancerPoolId references the particular pool in the balancer
        // contract which is used to exchange for the principal token
        bytes32 balancerPoolId;
        // The recipient is a target address the sender can send the resulting
        // principal tokens to
        address recipient;
        // Address of the principalToken
        IAsset principalToken;
        // The minimum amount of principal tokens the user expects to receive
        uint256 minPtAmount;
        // The time into the future for which the trade can happen
        uint256 deadline;
        // Some curvePools have themselves a dependent lpToken "root" which
        // this contract accommodates zapping through. This flag indicates if
        // such an action is necessary
        bool needsChildZap;
    }

    struct ZapCurveLpIn {
        // Address of target curvePool for which liquidity will be added
        // giving this contract the lpTokens necessary to swap for the
        // principalTokens
        address curvePool;
        // The target lpToken which will be received
        IERC20 lpToken;
        // Array of amounts which are structured in reference to the
        // "add_liquidity" function in the related curvePool. These in all
        // cases come in either fixed-length arrays of length 2 or 3
        uint256[] amounts;
        // Similar to "amounts", these are the reference token contract
        // addresses also ordered as per the inconsistent interface of the
        // "add_liquidity" curvePool function
        address[] roots;
        // Only relevant when there is a childZap, it references what
        // index in the amounts array of the main "zap" the resultant
        // number of lpTokens should be added to
        uint256 parentIdx;
        // The minimum amount of LP tokens expected to receive when adding
        // liquidity
        uint256 minLpAmount;
    }

    ///////////////////////////
    /// Zap Out Data Structure
    //////////////////////////

    struct ZapCurveLpOut {
        // Address of the curvePool for which an amount of lpTokens
        // is swapped for an amount of single root tokens
        address curvePool;
        // The contract address of the curve pools lpToken
        IERC20 lpToken;
        // This is the index of the target root we are swapping for
        int128 rootTokenIdx;
        // Address of the rootToken we are swapping for
        address rootToken;
        // This is the selector for deciding between the two differing curve
        // interfaces for the add
        bool curveRemoveLiqFnIsUint256;
    }

    struct ZapOutInfo {
        // Pool id of balancer pool that is used to exchange a users
        // amount of principal tokens
        bytes32 balancerPoolId;
        // Address of the principal token
        IAsset principalToken;
        // Amount of principal tokens the user wishes to swap for
        uint256 principalTokenAmount;
        // The recipient is the address the tokens which are to be swapped for
        // will be sent to
        address payable recipient;
        // The minimum amount base tokens the user is expecting
        uint256 minBaseTokenAmount;
        // The minimum amount root tokens the user is expecting
        uint256 minRootTokenAmount;
        // Timestamp into the future for which a transaction is valid for
        uint256 deadline;
        // If the target root token is sourced via two curve pool swaps, then
        // this is to be flagged as true
        bool targetNeedsChildZap;
    }

    /// @notice Memory encoding of the permit data
    struct PermitData {
        IERC20Permit tokenContract;
        address spender;
        uint256 amount;
        uint256 expiration;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    /// @notice Sets the msg.sender as authorized and also set it as the owner
    ///         in the authorizable contract.
    /// @param __balancer The balancer vault contract
    constructor(IVault __balancer) {
        _authorize(msg.sender);
        _balancer = __balancer;
        isFrozen = false;
    }

    /// @notice Requires that the contract is not frozen
    modifier notFrozen() {
        require(!isFrozen, "Contract frozen");
        _;
    }

    // Allow this contract to receive ether
    receive() external payable {}

    /// @notice Allows an authorized address to freeze or unfreeze this contract
    /// @param _newState True for frozen and false for unfrozen
    function setIsFrozen(bool _newState) external onlyAuthorized {
        isFrozen = _newState;
    }

    /// @notice Takes the input permit calls and executes them
    /// @param data The array which encodes the set of permit calls to make
    modifier preApproval(PermitData[] memory data) {
        // If permit calls are provided we make try to make them
        _permitCall(data);
        _;
    }

    /// @notice Makes permit calls indicated by a struct
    /// @param data the struct which has the permit calldata
    function _permitCall(PermitData[] memory data) internal {
        // Make the permit call to the token in the data field using
        // the fields provided.
        if (data.length != 0) {
            // We make permit calls for each indicated call
            for (uint256 i = 0; i < data.length; i++) {
                data[i].tokenContract.permit(
                    msg.sender,
                    data[i].spender,
                    data[i].amount,
                    data[i].expiration,
                    data[i].v,
                    data[i].r,
                    data[i].s
                );
            }
        }
    }

    /// @notice This function sets approvals on all ERC20 tokens.
    /// @param tokens An array of token addresses which are to be approved
    /// @param spenders An array of contract addresses, most likely curve and
    /// balancer pool addresses
    /// @param amounts An array of amounts for which at each index, the spender
    /// from the same index in the spenders array is approved to use the token
    /// at the equivalent index of the token array on behalf of this contract
    function setApprovalsFor(
        address[] memory tokens,
        address[] memory spenders,
        uint256[] memory amounts
    ) external onlyAuthorized {
        require(tokens.length == spenders.length, "Incorrect length");
        require(tokens.length == amounts.length, "Incorrect length");
        for (uint256 i = 0; i < tokens.length; i++) {
            // Below call is to make sure that previous allowance shouldn't revert the transaction
            // It is just a safety pattern to use.
            IERC20(tokens[i]).safeApprove(spenders[i], uint256(0));
            IERC20(tokens[i]).safeApprove(spenders[i], amounts[i]);
        }
    }

    /// @notice zapIn Exchanges a number of tokens which are used in a specific
    /// curve pool(s) for a principal token.
    /// @param _info See ZapInInfo struct
    /// @param _zap See ZapCurveLpIn struct - This is the "main" or parent zap
    /// which produces the lp token necessary to swap for the principal token
    /// @param _childZap See ZapCurveLpIn - This is used only in cases where
    /// the "main" or "parent" zap itself is composed of another curve lp token
    /// which can be accessed more readily via another swap via curve
    function zapIn(
        ZapInInfo memory _info,
        ZapCurveLpIn memory _zap,
        ZapCurveLpIn memory _childZap,
        PermitData[] memory _permitData
    )
        external
        payable
        nonReentrant
        notFrozen
        preApproval(_permitData)
        returns (uint256 ptAmount)
    {
        // Instantiation of the context amount container which is used to track
        // amounts to be swapped in the final curve zap.
        uint256[3] memory ctx;

        // Only execute the childZap if it is necessary
        if (_info.needsChildZap) {
            uint256 _amount = _zapCurveLpIn(
                _childZap,
                // The context array is unnecessary for the childZap and so we
                // can just put a dud array in place of it
                [uint256(0), uint256(0), uint256(0)]
            );
            // When a childZap happens, we add the amount of lpTokens gathered
            // from it to the relevant root index of the "main" zap
            ctx[_childZap.parentIdx] += _amount;
        }

        // Swap an amount of "root" tokens on curve for the lp token that is
        // used to then purchase the principal token
        uint256 baseTokenAmount = _zapCurveLpIn(_zap, ctx);

        // Purchase of "ptAmount" of principal tokens
        ptAmount = _balancer.swap(
            IVault.SingleSwap({
                poolId: _info.balancerPoolId,
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(address(_zap.lpToken)),
                assetOut: _info.principalToken,
                amount: baseTokenAmount,
                userData: "0x00"
            }),
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(_info.recipient),
                toInternalBalance: false
            }),
            _info.minPtAmount,
            _info.deadline
        );
    }

    /// @notice This function will add liquidity to a target curve pool,
    /// returning some amount of LP tokens as a result. This is effectively
    /// swapping amounts of the dependent curve pool tokens for the LP token
    /// which will be used elsewhere
    /// @param _zap ZapCurveLpIn struct
    /// @param _ctx fixed length array used as an amounts container between the
    /// zap and childZap and also makes the transition from a dynamic-length
    /// array to a fixed-length which is required for the actual call to add
    /// liquidity to the curvePool
    function _zapCurveLpIn(ZapCurveLpIn memory _zap, uint256[3] memory _ctx)
        internal
        returns (uint256)
    {
        // All curvePools have either 2 or 3 "root" tokens
        require(
            _zap.amounts.length == 2 || _zap.amounts.length == 3,
            "!(2 >= amounts.length <= 3)"
        );

        // Flag to detect if a zap to curve should be made
        bool shouldMakeZap = false;
        for (uint8 i = 0; i < _zap.amounts.length; i++) {
            bool zapIndexHasAmount = _zap.amounts[i] > 0;
            // If either the _ctx or zap amounts array has an index with an
            // amount > 0 we must zap curve
            shouldMakeZap = (zapIndexHasAmount || _ctx[i] > 0)
                ? true
                : shouldMakeZap;

            // if there is no amount at this index we can escape the loop earlier
            if (!zapIndexHasAmount) continue;

            if (_zap.roots[i] == _ETH_CONSTANT) {
                // Must check we do not unintentionally send ETH
                require(msg.value == _zap.amounts[i], "incorrect value");

                // We build the context container with our amounts
                _ctx[i] += _zap.amounts[i];
            } else {
                uint256 beforeAmount = _getBalanceOf(IERC20(_zap.roots[i]));

                // In the case of swapping an ERC20 "root" we must transfer them
                // to this contract in order to make the exchange
                IERC20(_zap.roots[i]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _zap.amounts[i]
                );

                // Due to rounding issues of some tokens, we use the
                // differential token balance of this contract
                _ctx[i] += _getBalanceOf(IERC20(_zap.roots[i])) - beforeAmount;
            }
        }

        // When there is nothing to swap for on curve we short-circuit
        if (!shouldMakeZap) {
            return 0;
        }
        uint256 beforeLpTokenBalance = _getBalanceOf(_zap.lpToken);

        if (_zap.amounts.length == 2) {
            ICurvePool(_zap.curvePool).add_liquidity{ value: msg.value }(
                [_ctx[0], _ctx[1]],
                _zap.minLpAmount
            );
        } else {
            ICurvePool(_zap.curvePool).add_liquidity{ value: msg.value }(
                [_ctx[0], _ctx[1], _ctx[2]],
                _zap.minLpAmount
            );
        }

        return _getBalanceOf(_zap.lpToken) - beforeLpTokenBalance;
    }

    /// @notice zapOut Allows users sell their principalTokens and subsequently
    /// swap the resultant curve LP token for one of its dependent "root tokens"
    /// @param _info See ZapOutInfo
    /// @param _zap See ZapCurveLpOut
    /// @param _childZap See ZapCurveLpOut
    function zapOut(
        ZapOutInfo memory _info,
        ZapCurveLpOut memory _zap,
        ZapCurveLpOut memory _childZap,
        PermitData[] memory _permitData
    )
        external
        payable
        nonReentrant
        notFrozen
        preApproval(_permitData)
        returns (uint256 amount)
    {
        // First, principalTokenAmount of principal tokens transferred
        // from sender to this contract
        IERC20(address(_info.principalToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _info.principalTokenAmount
        );

        // Swaps an amount of users principal tokens for baseTokens, which
        // are the lpToken specified in the zap argument
        uint256 baseTokenAmount = _balancer.swap(
            IVault.SingleSwap({
                poolId: _info.balancerPoolId,
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: _info.principalToken,
                assetOut: IAsset(address(_zap.lpToken)),
                amount: _info.principalTokenAmount,
                userData: "0x00"
            }),
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            _info.minBaseTokenAmount,
            _info.deadline
        );

        // Swap the baseTokens for a target root. In the case of where the
        // specified token the user wants is part of the childZap, the zap that
        // occurs is to swap the baseTokens to the lpToken specified in the
        // childZap struct. If there is no childZap, then the contract sends
        // the tokens to the recipient
        amount = _zapCurveLpOut(
            _zap,
            baseTokenAmount,
            _info.targetNeedsChildZap ? 0 : _info.minRootTokenAmount,
            _info.targetNeedsChildZap ? payable(address(this)) : _info.recipient
        );

        // Execute the childZap is specified to do so
        if (_info.targetNeedsChildZap) {
            amount = _zapCurveLpOut(
                _childZap,
                amount,
                _info.minRootTokenAmount,
                _info.recipient
            );
        }
    }

    /// @notice Swaps an amount of curve LP tokens for a single root token
    /// @param _zap See ZapCurveLpOut
    /// @param _lpTokenAmount This is the amount of lpTokens we are swapping
    /// with
    /// @param _minRootTokenAmount This is the minimum amount of "root" tokens
    /// the user expects to swap for. Used only in the final zap when executed
    /// under zapOut
    /// @param _recipient The address which the outputs tokens are to be sent
    /// to. When there is a second zap to occur, in the first zap the recipient
    /// should be this address
    function _zapCurveLpOut(
        ZapCurveLpOut memory _zap,
        uint256 _lpTokenAmount,
        uint256 _minRootTokenAmount,
        address payable _recipient
    ) internal returns (uint256 rootAmount) {
        // Flag to detect if we are sending to recipient
        bool transferToRecipient = address(this) != _recipient;
        uint256 beforeAmount = _zap.rootToken == _ETH_CONSTANT
            ? address(this).balance
            : _getBalanceOf(IERC20(_zap.rootToken));

        if (_zap.curveRemoveLiqFnIsUint256) {
            ICurvePool(_zap.curvePool).remove_liquidity_one_coin(
                _lpTokenAmount,
                uint256(int256(_zap.rootTokenIdx)),
                _minRootTokenAmount
            );
        } else {
            ICurvePool(_zap.curvePool).remove_liquidity_one_coin(
                _lpTokenAmount,
                _zap.rootTokenIdx,
                _minRootTokenAmount
            );
        }

        // ETH case
        if (_zap.rootToken == _ETH_CONSTANT) {
            // Get ETH balance of current contract
            rootAmount = address(this).balance - beforeAmount;
            // if address does not equal this contract we send funds to recipient
            if (transferToRecipient) {
                // Send rootAmount of ETH to the user-specified recipient
                _recipient.transfer(rootAmount);
            }
        } else {
            // Get balance of root token that was swapped
            rootAmount = _getBalanceOf(IERC20(_zap.rootToken)) - beforeAmount;
            // Send tokens to recipient
            if (transferToRecipient) {
                IERC20(_zap.rootToken).safeTransferFrom(
                    address(this),
                    _recipient,
                    rootAmount
                );
            }
        }
    }

    function _getBalanceOf(IERC20 _token) internal view returns (uint256) {
        return _token.balanceOf(address(this));
    }
}
