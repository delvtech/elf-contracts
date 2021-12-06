// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../libraries/Authorizable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IAsset {}

interface IVault {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    enum PoolSpecialization {
        GENERAL,
        MINIMAL_SWAP_INFO,
        TWO_TOKEN
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);

    function getPool(bytes32 poolId)
        external
        view
        returns (address, PoolSpecialization);
}

contract ZapCurveTokenToPrincipalToken is Authorizable {
    // Enables a more consistent interface when utilising ERC20 tokens
    using SafeERC20 for IERC20;
    // Simplifies making low-level function calls
    using Address for address;

    // Store the accessibility state of the contract
    bool public isFrozen = false;

    // A constant to represent ether
    address internal constant _ETH_CONSTANT =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // Reference to the main balancer vault
    IVault internal immutable _balancer;

    /// @dev Marks the msg.sender as authorized and sets them as the owner
    ///      in the authorization library
    /// @param __balancer The balancer vault contract
    constructor(IVault __balancer) Authorizable() {
        _authorize(msg.sender);
        _balancer = __balancer;
    }

    /// @dev Allows this contract to receive ether
    receive() external payable {}

    /// @dev This function sets approvals on all ERC20 tokens
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
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeApprove(spenders[i], amounts[i]);
        }
    }

    /// @dev Requires that the contract is not frozen
    modifier notFrozen() {
        require(!isFrozen, "Contract frozen");
        _;
    }

    /// @dev Allows an authorized address to freeze or unfreeze this contract
    /// @param _newState True for frozen and false for unfrozen
    function setIsFrozen(bool _newState) external onlyAuthorized {
        isFrozen = _newState;
    }

    struct ZapInInfo {
        // The balancerPoolId references the particular pool in the balancer
        // contract which is used to exchange for the principal token
        bytes32 balancerPoolId;
        // The recipient is a target address the sender can send the resulting
        // principal tokens to
        address recipient;
        // Address of the principalToken
        IAsset principalToken;
        // The minimum amount of principal tokens the user expects to recieve
        uint256 minPtAmount;
        // The time into the future for which the trade can happen
        uint256 deadline;
        // Some curvePools have themselves a dependent lpToken "root" which
        // this contract accomodates zapping through. This flag indicates if
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
        // This is the function signature for the "add_liquidity" function
        // which must be constructed on the frontend as the suite of curvePool
        // contracts have an inconsistent interface.
        bytes4 funcSig;
    }

    /// @dev Effectively exchanges an array of "root" tokens for an amount of
    /// curve lpTokens
    /// @param _zap ZapCurveLpIn struct
    /// @param _ctx fixed length array used as an amounts container between the
    /// zap and childZap and also makes the transition from a dynamic-length
    /// array to a fixed-length which is required for the actual call to add
    /// liquidity to the curvePool
    function _zapCurveLpIn(ZapCurveLpIn memory _zap, uint256[3] memory ctx)
        internal
        returns (uint256)
    {
        // All curvePools have either 2 or 3 "root" tokens
        require(
            _zap.amounts.length == 2 || _zap.amounts.length == 3,
            "!(2 >= amounts.length <= 3)"
        );

        // Flag if the current zap has amounts. Used to short-circuit
        // unneccessary calls
        bool zapHasAmounts = false;
        // Flag for where the user has a childZap with amounts. Used to
        // short-cicuit unneccessary calls
        bool ctxHasAmounts = false;
        for (uint8 i = 0; i < _zap.amounts.length; i++) {
            // Must check we do not unintentionally send ETH
            if (_zap.roots[i] == _ETH_CONSTANT)
                require(msg.value == _zap.amounts[i], "incorrect value");

            // Setting ctxHasAmounts flag as true means that there
            // was a previous childZap we must acknowledge
            if (!ctxHasAmounts && ctx[i] > 0) {
                ctxHasAmounts = true;
            }

            if (_zap.amounts[i] > 0) {
                // If the zapHasAmounts has not been set, we set it to true
                if (!zapHasAmounts) {
                    zapHasAmounts = true;
                }

                if (_zap.roots[i] == _ETH_CONSTANT) {
                    // We build the context container with our amounts
                    ctx[i] += _zap.amounts[i];
                } else {
                    // In the case of swapping an ERC20 "root" we must transfer them
                    // to this contract in order to make the exchange
                    IERC20(_zap.roots[i]).safeTransferFrom(
                        msg.sender,
                        address(this),
                        _zap.amounts[i]
                    );

                    // Due to rounding issues of some tokens, we find the
                    // relevant token balance of this contract
                    ctx[i] = IERC20(_zap.roots[i]).balanceOf(address(this));
                }
            }
        }

        // When we do not have anything to swap for, we short-circuit
        if (!zapHasAmounts && !ctxHasAmounts) {
            return 0;
        }

        // It is necessary to add liquidity to the respective curve pool like
        // this due to the non-standard interface of the function in the curve
        // contracts. Not only is there two variants of fixed length array
        // amount inputs but it is often inconsistent whether return values
        // exist or not
        // Also, the context amounts container, although fixed-length of 2 or 3,
        // because it is a low-level function call, solidity will not complain
        // and the first 2 indexes are only considered in the case of it being
        // length 2
        address(_zap.curvePool).functionCallWithValue(
            abi.encodeWithSelector(_zap.funcSig, ctx, 0),
            msg.value
        );

        return _zap.lpToken.balanceOf(address(this));
    }

    /// @dev zapIn enables the user swap multiple dependent curve tokens into
    /// their respective lp tokens and then immediately swaps them for
    /// principal tokens, greatly simplifying the purchasing of principal
    /// tokens
    /// @param _info See ZapInInfo struct
    /// @param _zap See ZapCurveLpIn struct - This is the "main" or parent zap
    /// which produces the lp token necessary to swap for the principal token
    /// @param _childZap See ZapCurveLpIn - This is used only in cases where
    /// the "main" or "parent" zap itself is composed of another curve lp token
    /// which can be accessed more readily via another swap via curve
    function zapIn(
        ZapInInfo memory _info,
        ZapCurveLpIn memory _zap,
        ZapCurveLpIn memory _childZap
    ) external payable notFrozen returns (uint256 ptAmount) {
        // Instantiation of the context amount container which is used to track
        // amounts to be swapped in the final curve zap.
        uint256[3] memory ctx;

        // Only execute the childZap if it is necessary
        if (_info.needsChildZap) {
            uint256 _amount = _zapCurveLpIn(
                _childZap,
                // The context array is unneccessary for the childZap and so we
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
        // This is the function signature of the curvePool's
        // "remove_liquidity_one_coin" function which similar to the
        // "add_liquidity" curvePool function in the zapIn, there is
        // an inconsistent interface when interacting with curve pools
        bytes4 funcSig;
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
        // The minimum amount root tokens the user is expecting
        uint256 minRootTokenAmount;
        // Timestamp into the future for which a transaction is valid for
        uint256 deadline;
        // If the target root token is sourced via two curve pool swaps, then
        // this is to be flagged as true
        bool targetNeedsChildZap;
    }

    /// @dev Swaps an amount of curve lptokens for a single dependent root token
    /// from its pool
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

        // Actual swap of lpToken -> rootToken
        address(_zap.curvePool).functionCall(
            abi.encodeWithSelector(
                _zap.funcSig,
                _lpTokenAmount,
                _zap.rootTokenIdx,
                _minRootTokenAmount
            )
        );

        // ETH case
        if (_zap.rootToken == _ETH_CONSTANT) {
            // Get ETH balance of current contract
            rootAmount = address(this).balance;
            // if address does not equal this contract we send funds to recipient
            if (transferToRecipient) {
                // Send rootAmount of ETH to the user-specified recipient
                _recipient.transfer(rootAmount);
            }
        } else {
            // Get balance of root token that was swapped
            rootAmount = IERC20(_zap.rootToken).balanceOf(address(this));
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

    /// @dev zapOut Allows users sell their principalTokens and subsequently
    /// swap the resultant curve lpToken for one of its dependent "root" tokens
    /// @param _info See ZapOutInfo
    /// @param _zap See ZapCurveLpOut
    /// @param _childZap See ZapCurveLpOut
    function zapOut(
        ZapOutInfo memory _info,
        ZapCurveLpOut memory _zap,
        ZapCurveLpOut memory _childZap
    ) external payable notFrozen returns (uint256 amount) {
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
            0,
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
}
