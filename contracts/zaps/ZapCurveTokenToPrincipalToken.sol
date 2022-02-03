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
        IAsset principalToken;
        uint256 minPtAmount;
        uint256 deadline;
        bool needsChildZap;
    }

    struct ZapCurveLpIn {
        address curvePool;
        IERC20 lpToken;
        uint256[] amounts;
        address[] roots;
        uint256 parentIdx;
        bytes4 funcSig;
        uint256 minLpAmount;
    }

    struct ZapCurveLpOut {
        address curvePool;
        IERC20 lpToken;
        uint256 rootTokenIdx;
        address rootToken;
        bool isSigUint256;
    }

    struct ZapOutInfo {
        bytes32 balancerPoolId;
        IAsset principalToken;
        uint256 principalTokenAmount;
        address payable recipient;
        uint256 minBaseTokenAmount;
        uint256 minRootTokenAmount;
        uint256 deadline;
        bool targetNeedsChildZap;
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
        uint256[3] memory ctx;

        if (_info.needsChildZap) {
            uint256 _amount = _zapCurveLpIn(
                _childZap,
                [uint256(0), uint256(0), uint256(0)]
            );
            ctx[_childZap.parentIdx] += _amount;
        }

        uint256 baseTokenAmount = _zapCurveLpIn(_zap, ctx);

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

    function _zapCurveLpIn(ZapCurveLpIn memory _zap, uint256[3] memory _ctx)
        internal
        returns (uint256)
    {
        require(
            _zap.amounts.length == 2 || _zap.amounts.length == 3,
            "!(2 >= amounts.length <= 3)"
        );

        bool shouldMakeZap = false;
        for (uint8 i = 0; i < _zap.amounts.length; i++) {
            bool zapIndexHasAmount = _zap.amounts[i] > 0;

            shouldMakeZap = (zapIndexHasAmount || _ctx[i] > 0)
                ? true
                : shouldMakeZap;

            if (!zapIndexHasAmount) continue;

            if (_zap.roots[i] == _ETH_CONSTANT) {
                require(msg.value == _zap.amounts[i], "incorrect value");

                _ctx[i] += _zap.amounts[i];
            } else {
                uint256 beforeAmount = _getBalanceOf(IERC20(_zap.roots[i]));

                IERC20(_zap.roots[i]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _zap.amounts[i]
                );

                _ctx[i] += _getBalanceOf(IERC20(_zap.roots[i])) - beforeAmount;
            }
        }

        if (!shouldMakeZap) {
            return 0;
        }
        uint256 beforeLpTokenBalance = _getBalanceOf(_zap.lpToken);

        address(_zap.curvePool).functionCallWithValue(
            abi.encodeWithSelector(_zap.funcSig, _ctx, _zap.minLpAmount),
            msg.value
        );

        return _getBalanceOf(_zap.lpToken) - beforeLpTokenBalance;
    }

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
        IERC20(address(_info.principalToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _info.principalTokenAmount
        );

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

        amount = _zapCurveLpOut(
            _zap,
            baseTokenAmount,
            _info.targetNeedsChildZap ? 0 : _info.minRootTokenAmount,
            _info.targetNeedsChildZap ? payable(address(this)) : _info.recipient
        );

        if (_info.targetNeedsChildZap) {
            amount = _zapCurveLpOut(
                _childZap,
                amount,
                _info.minRootTokenAmount,
                _info.recipient
            );
        }
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

    function _getBalanceOf(IERC20 _token) internal view returns (uint256) {
        return _token.balanceOf(address(this));
    }
}
