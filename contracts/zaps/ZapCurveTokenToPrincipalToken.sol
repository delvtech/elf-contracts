// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

import "../libraries/Authorizable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IVault.sol";
import "../interfaces/ICurvePool.sol";

contract ZapCurveTokenToPrincipalToken is Authorizable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    bool public isFrozen;

    address internal constant _ETH_CONSTANT =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    IVault internal immutable _balancer;

    struct ZapInInfo {
        bytes32 balancerPoolId;
        address recipient;
        address principalToken;
        uint256 minPtAmount;
        uint256 deadline;
    }

    struct ZapCurveLpIn {
        address curvePool;
        address lpToken;
        uint256[] amounts;
        address[] roots;
        uint256 parentIdx;
        uint256 minLpAmount;
    }

    struct ZapCurveLpOut {
        address curvePool;
        address lpToken;
        uint256 rootTokenIdx;
        address rootToken;
        bool isSigUint256;
    }

    struct ZapOutInfo {
        bytes32 balancerPoolId;
        address principalToken;
        uint256 principalTokenAmount;
        address payable recipient;
        uint256 minBaseTokenAmount;
        uint256 minRootTokenAmount;
        uint256 deadline;
    }

    struct PermitData {
        IERC20Permit tokenContract;
        address spender;
        uint256 amount;
        uint256 expiration;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    constructor(IVault __balancer) {
        _authorize(msg.sender);
        _balancer = __balancer;
        isFrozen = false;
    }

    modifier notFrozen() {
        require(!isFrozen, "Contract frozen");
        _;
    }

    receive() external payable {}

    function setIsFrozen(bool _newState) external onlyAuthorized {
        isFrozen = _newState;
    }

    modifier preApproval(PermitData[] memory data) {
        _permitCall(data);
        _;
    }

    function _permitCall(PermitData[] memory data) internal {
        if (data.length != 0) {
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

    function setApprovalsFor(
        address[] memory tokens,
        address[] memory spenders,
        uint256[] memory amounts
    ) external onlyAuthorized {
        require(tokens.length == spenders.length, "Incorrect length");
        require(tokens.length == amounts.length, "Incorrect length");
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeApprove(spenders[i], uint256(0));
            IERC20(tokens[i]).safeApprove(spenders[i], amounts[i]);
        }
    }

    function zapIn(
        ZapInInfo memory _info,
        ZapCurveLpIn memory _zap,
        PermitData[] memory _permitData
    )
        external
        payable
        nonReentrant
        notFrozen
        preApproval(_permitData)
        returns (uint256)
    {
        return
            _zapIn(
                ZapIn({
                    pool: _zap.curvePool,
                    poolToken: _zap.lpToken,
                    amounts: _zap.amounts,
                    tokens: _zap.roots,
                    minAmount: _info.minPtAmount,
                    balancerPoolId: _info.balancerPoolId,
                    principalToken: _info.principalToken,
                    recipient: _info.recipient,
                    deadline: _info.deadline
                })
            );
    }

    function zapInWithChild(
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
        returns (uint256)
    {
        _zap.amounts[_childZap.parentIdx] += _curvePoolSwapTokensToLp(
            CurvePoolSwapTokensToLp({
                pool: _childZap.curvePool,
                poolToken: _childZap.lpToken,
                amounts: _childZap.amounts,
                tokens: _childZap.roots,
                minAmount: 0
            })
        );
        return
            _zapIn(
                ZapIn({
                    pool: _zap.curvePool,
                    poolToken: _zap.lpToken,
                    amounts: _zap.amounts,
                    tokens: _zap.roots,
                    minAmount: _info.minPtAmount,
                    balancerPoolId: _info.balancerPoolId,
                    principalToken: _info.principalToken,
                    recipient: _info.recipient,
                    deadline: _info.deadline
                })
            );
    }

    struct ZapIn {
        address pool; // curve pool address
        address poolToken; // lp token of curve pool
        uint256[] amounts;
        address[] tokens;
        uint256 minAmount; // min amount of pt to be returned
        bytes32 balancerPoolId;
        address principalToken;
        address recipient;
        uint256 deadline;
    }

    function _zapIn(ZapIn memory _zap) internal returns (uint256) {
        return
            _balancerSwap(
                BalancerSwap({
                    poolId: _zap.balancerPoolId,
                    assetIn: _zap.poolToken,
                    assetOut: _zap.principalToken,
                    amount: _curvePoolSwapTokensToLp(
                        CurvePoolSwapTokensToLp({
                            pool: _zap.pool,
                            poolToken: _zap.poolToken,
                            amounts: _zap.amounts,
                            tokens: _zap.tokens,
                            minAmount: 0
                        })
                    ),
                    recipient: _zap.recipient,
                    minAmount: _zap.minAmount,
                    deadline: _zap.deadline
                })
            );
    }

    struct CurvePoolSwapTokensToLp {
        address pool; // curve pool address
        address poolToken; // lp token of curve pool
        uint256[] amounts;
        address[] tokens;
        uint256 minAmount; // min amount of lp to be returned
    }

    function _curvePoolSwapTokensToLp(CurvePoolSwapTokensToLp memory _swap)
        internal
        returns (uint256)
    {
        require(
            (_swap.amounts.length == 2 || _swap.amounts.length == 3) &&
                (_swap.tokens.length == _swap.amounts.length),
            "invalid input"
        );

        bool tokenIsEther = false;
        for (uint8 i = 0; i < _swap.amounts.length; i++) {
            if (_swap.tokens[i] == _ETH_CONSTANT) {
                require(msg.value == _swap.amounts[i], "incorrect value");
                tokenIsEther = true;
            } else {
                uint256 beforeAmount = _getBalanceOf(IERC20(_swap.tokens[i]));

                IERC20(_swap.tokens[i]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _swap.amounts[i]
                );
                // This mutates by reference
                _swap.amounts[i] =
                    _getBalanceOf(IERC20(_swap.tokens[i])) -
                    beforeAmount;
            }
        }

        uint256 beforeLpTokenBalance = _getBalanceOf(IERC20(_swap.poolToken));

        if (_swap.amounts.length == 2) {
            ICurvePool(_swap.pool).add_liquidity{
                value: tokenIsEther ? msg.value : 0
            }([_swap.amounts[0], _swap.amounts[1]], _swap.minAmount);
        } else {
            ICurvePool(_swap.pool).add_liquidity{
                value: tokenIsEther ? msg.value : 0
            }(
                [_swap.amounts[0], _swap.amounts[1], _swap.amounts[2]],
                _swap.minAmount
            );
        }

        return _getBalanceOf(IERC20(_swap.poolToken)) - beforeLpTokenBalance;
    }

    function zapOut(
        ZapOutInfo memory _info,
        ZapCurveLpOut memory _zap,
        PermitData[] memory _permitData
    )
        external
        payable
        nonReentrant
        notFrozen
        preApproval(_permitData)
        returns (uint256)
    {
        return
            _zapOut(
                ZapOut({
                    principalToken: _info.principalToken,
                    amount: _info.principalTokenAmount,
                    balancerPoolId: _info.balancerPoolId,
                    recipient: _info.recipient,
                    pool: _zap.curvePool,
                    poolToken: _zap.lpToken,
                    token: _zap.rootToken,
                    tokenIdx: _zap.rootTokenIdx,
                    isSigUint256: _zap.isSigUint256,
                    minAmount: _info.minRootTokenAmount,
                    deadline: _info.deadline
                })
            );
    }

    function zapOutWithChild(
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
        returns (uint256)
    {
        return
            _curvePoolSwapLpToToken(
                CurvePoolSwapLpToToken({
                    pool: _childZap.curvePool,
                    token: _childZap.rootToken,
                    tokenIdx: _childZap.rootTokenIdx,
                    isSigUint256: _childZap.isSigUint256,
                    amount: _zapOut(
                        ZapOut({
                            principalToken: _info.principalToken,
                            amount: _info.principalTokenAmount,
                            balancerPoolId: _info.balancerPoolId,
                            recipient: address(this),
                            pool: _zap.curvePool,
                            poolToken: _zap.lpToken,
                            token: _zap.rootToken,
                            tokenIdx: _zap.rootTokenIdx,
                            isSigUint256: _zap.isSigUint256,
                            minAmount: 0,
                            deadline: _info.deadline
                        })
                    ),
                    minAmount: _info.minRootTokenAmount,
                    recipient: _info.recipient
                })
            );
    }

    struct ZapOut {
        address principalToken;
        uint256 amount; // amount of pt's
        bytes32 balancerPoolId;
        address recipient;
        address pool; // curve pool to change
        address poolToken;
        address token;
        uint256 tokenIdx;
        bool isSigUint256;
        uint256 deadline;
        uint256 minAmount;
    }

    function _zapOut(ZapOut memory _zap) internal returns (uint256) {
        IERC20(_zap.principalToken).safeTransferFrom(
            msg.sender,
            address(this),
            _zap.amount
        );

        return
            _curvePoolSwapLpToToken(
                CurvePoolSwapLpToToken({
                    pool: _zap.pool,
                    token: _zap.token,
                    tokenIdx: _zap.tokenIdx,
                    isSigUint256: _zap.isSigUint256,
                    amount: _balancerSwap(
                        BalancerSwap({
                            poolId: _zap.balancerPoolId,
                            assetIn: _zap.principalToken,
                            assetOut: _zap.poolToken,
                            amount: _zap.amount,
                            recipient: address(this),
                            minAmount: 0, // don't care about intermediary swap, will revert on curve swap
                            deadline: _zap.deadline
                        })
                    ),
                    minAmount: _zap.minAmount,
                    recipient: _zap.recipient
                })
            );
    }

    struct CurvePoolSwapLpToToken {
        address pool; // curve pool
        address token; // token the lpToken will be swapped for
        uint256 tokenIdx; // index of token in coins array of pool
        bool isSigUint256; // great to get rid of this
        uint256 amount; // amount of lp tokens to be swapped for a given pool token
        uint256 minAmount; // minimum amount of pool tokens to be swapped for
        address recipient;
    }

    function _curvePoolSwapLpToToken(CurvePoolSwapLpToToken memory _swap)
        internal
        returns (uint256 tokenAmountReceived)
    {
        bool transferToRecipient = address(this) != _swap.recipient;
        bool tokenIsEther = _swap.token == _ETH_CONSTANT;
        uint256 beforeAmount = tokenIsEther
            ? address(this).balance
            : _getBalanceOf(IERC20(_swap.token));

        if (_swap.isSigUint256) {
            ICurvePool(_swap.pool).remove_liquidity_one_coin(
                _swap.amount,
                _swap.tokenIdx,
                _swap.minAmount
            );
        } else {
            ICurvePool(_swap.pool).remove_liquidity_one_coin(
                _swap.amount,
                int128(int256(_swap.tokenIdx)),
                _swap.minAmount
            );
        }

        if (tokenIsEther) {
            tokenAmountReceived = address(this).balance - beforeAmount;
            if (transferToRecipient) {
                payable(_swap.recipient).transfer(tokenAmountReceived);
            }
        } else {
            tokenAmountReceived =
                _getBalanceOf(IERC20(_swap.token)) -
                beforeAmount;
            if (transferToRecipient) {
                IERC20(_swap.token).safeTransferFrom(
                    address(this),
                    _swap.recipient,
                    tokenAmountReceived
                );
            }
        }
    }

    struct BalancerSwap {
        bytes32 poolId;
        address assetIn;
        address assetOut;
        uint256 amount;
        address recipient;
        uint256 minAmount;
        uint256 deadline;
    }

    // always
    function _balancerSwap(BalancerSwap memory _swap)
        internal
        returns (uint256)
    {
        return
            _balancer.swap(
                IVault.SingleSwap({
                    poolId: _swap.poolId,
                    kind: IVault.SwapKind.GIVEN_IN,
                    assetIn: IAsset(_swap.assetIn),
                    assetOut: IAsset(_swap.assetOut),
                    amount: _swap.amount,
                    userData: "0x00"
                }),
                IVault.FundManagement({
                    sender: address(this),
                    fromInternalBalance: false,
                    recipient: payable(_swap.recipient),
                    toInternalBalance: false
                }),
                _swap.minAmount,
                _swap.deadline
            );
    }

    function _getBalanceOf(IERC20 _token) internal view returns (uint256) {
        return _token.balanceOf(address(this));
    }
}
