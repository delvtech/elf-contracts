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
        return _zapIn(_info, _zap);
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
        _zap.amounts[_childZap.parentIdx] += _zapCurveLpIn(_childZap);
        return _zapIn(_info, _zap);
    }

    function _zapIn(ZapInInfo memory _info, ZapCurveLpIn memory _zap)
        internal
        returns (uint256)
    {
        return
            _balancerSwap(
                BalancerSwap({
                    poolId: _info.balancerPoolId,
                    assetIn: address(_zap.lpToken),
                    assetOut: _info.principalToken,
                    amount: _zapCurveLpIn(_zap),
                    recipient: _info.recipient,
                    minAmount: _info.minPtAmount,
                    deadline: _info.deadline
                })
            );
    }

    function _zapCurveLpIn(ZapCurveLpIn memory _zap)
        internal
        returns (uint256)
    {
        require(
            _zap.amounts.length == 2 || _zap.amounts.length == 3,
            "!(2 >= amounts.length <= 3)"
        );

        bool sendingEth = false;
        for (uint8 i = 0; i < _zap.amounts.length; i++) {
            if (_zap.roots[i] == _ETH_CONSTANT) {
                require(msg.value == _zap.amounts[i], "incorrect value");
                sendingEth = true;
            } else {
                uint256 beforeAmount = _getBalanceOf(IERC20(_zap.roots[i]));

                IERC20(_zap.roots[i]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _zap.amounts[i]
                );
                // This mutates by reference
                _zap.amounts[i] =
                    _getBalanceOf(IERC20(_zap.roots[i])) -
                    beforeAmount;
            }
        }

        uint256 beforeLpTokenBalance = _getBalanceOf(IERC20(_zap.lpToken));

        _zap.amounts.length == 2
            ? ICurvePool(_zap.curvePool).add_liquidity{
                value: sendingEth ? msg.value : 0
            }([_zap.amounts[0], _zap.amounts[1]], _zap.minLpAmount)
            : ICurvePool(_zap.curvePool).add_liquidity{
                value: sendingEth ? msg.value : 0
            }(
                [_zap.amounts[0], _zap.amounts[1], _zap.amounts[2]],
                _zap.minLpAmount
            );

        return _getBalanceOf(IERC20(_zap.lpToken)) - beforeLpTokenBalance;
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
        return _zapOut(_info, _zap);
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
            _zapCurveLpOut(
                _childZap,
                _zapOut(
                    ZapOutInfo({
                        balancerPoolId: _info.balancerPoolId,
                        principalToken: _info.principalToken,
                        principalTokenAmount: _info.principalTokenAmount,
                        recipient: payable(address(this)),
                        minBaseTokenAmount: _info.minBaseTokenAmount,
                        minRootTokenAmount: 0,
                        deadline: _info.deadline
                    }),
                    _zap
                ),
                _info.minRootTokenAmount,
                _info.recipient
            );
    }

    function _zapOut(ZapOutInfo memory _info, ZapCurveLpOut memory _zap)
        internal
        returns (uint256)
    {
        IERC20(address(_info.principalToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _info.principalTokenAmount
        );

        uint256 baseTokenAmount = _balancerSwap(
            BalancerSwap({
                poolId: _info.balancerPoolId,
                assetIn: _info.principalToken,
                assetOut: _zap.lpToken,
                amount: _info.principalTokenAmount,
                recipient: address(this),
                minAmount: _info.minBaseTokenAmount,
                deadline: _info.deadline // maybe this at end?
            })
        );

        return
            _zapCurveLpOut(
                _zap,
                baseTokenAmount,
                _info.minRootTokenAmount,
                _info.recipient
            );
    }

    function _zapCurveLpOut(
        ZapCurveLpOut memory _zap,
        uint256 _lpTokenAmount,
        uint256 _minRootTokenAmount,
        address payable _recipient
    ) internal returns (uint256 rootAmount) {
        bool transferToRecipient = address(this) != _recipient;
        uint256 beforeAmount = _zap.rootToken == _ETH_CONSTANT
            ? address(this).balance
            : _getBalanceOf(IERC20(_zap.rootToken));

        _zap.isSigUint256
            ? ICurvePool(_zap.curvePool).remove_liquidity_one_coin(
                _lpTokenAmount,
                _zap.rootTokenIdx,
                _minRootTokenAmount
            )
            : ICurvePool(_zap.curvePool).remove_liquidity_one_coin(
                _lpTokenAmount,
                int128(int256(_zap.rootTokenIdx)),
                _minRootTokenAmount
            );

        if (_zap.rootToken == _ETH_CONSTANT) {
            rootAmount = address(this).balance - beforeAmount;
            if (transferToRecipient) {
                _recipient.transfer(rootAmount);
            }
        } else {
            rootAmount = _getBalanceOf(IERC20(_zap.rootToken)) - beforeAmount;
            if (transferToRecipient) {
                IERC20(_zap.rootToken).safeTransferFrom(
                    address(this),
                    _recipient,
                    rootAmount
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
    function _balancerSwap(BalancerSwap memory _balancerSwap)
        internal
        returns (uint256)
    {
        return
            _balancer.swap(
                IVault.SingleSwap({
                    poolId: _balancerSwap.poolId,
                    kind: IVault.SwapKind.GIVEN_IN,
                    assetIn: IAsset(_balancerSwap.assetIn),
                    assetOut: IAsset(_balancerSwap.assetOut),
                    amount: _balancerSwap.amount,
                    userData: "0x00"
                }),
                IVault.FundManagement({
                    sender: address(this),
                    fromInternalBalance: false,
                    recipient: payable(_balancerSwap.recipient),
                    toInternalBalance: false
                }),
                _balancerSwap.minAmount,
                _balancerSwap.deadline
            );
    }

    function _getBalanceOf(IERC20 _token) internal view returns (uint256) {
        return _token.balanceOf(address(this));
    }
}
