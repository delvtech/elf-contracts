// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "hardhat/console.sol";

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

contract ZapCurveToPt is Authorizable {
    using SafeERC20 for IERC20;
    using Address for address;

    bool public isFrozen = false;

    address internal constant _ETH_CONSTANT =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    IVault internal immutable _balancer;

    constructor(IVault __balancer) Authorizable() {
        _authorize(msg.sender);
        _balancer = __balancer;
    }

    bool private _noReentry = false;

    modifier reentrancyGuard() {
        require(!_noReentry);
        _noReentry = true;
        _;
        _noReentry = false;
    }

    function setApprovalsFor(address[] memory tokens, address[] memory spenders)
        external
        onlyAuthorized
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeApprove(spenders[i], type(uint256).max);
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

    struct ZapCurveLp {
        address curvePool;
        IERC20 lpToken;
        uint256[] amounts;
        address[] roots;
        uint256 parentIdx;
    }

    struct ZapPtInfo {
        bytes32 balancerPoolId;
        address payable recipient;
        IAsset principalToken;
        uint256 minPtAmount;
        uint256 deadline;
    }

    function _zapCurveLp(ZapCurveLp memory _zap) internal returns (uint256) {
        uint256[3] memory ctx;
        return _zapCurveLp(_zap, ctx);
    }

    // Given that we call the curve add liquidity function through a low-level
    // call, we can utilise a fixed-length array of length 3 as our input context
    // "bucket". In the event where the target curve pool contract expects an
    // array of length 2, we can still utilise the "bucket" where the last index is
    // disregarded.
    function _zapCurveLp(ZapCurveLp memory _zap, uint256[3] memory ctx)
        internal
        returns (uint256)
    {
        require(
            _zap.amounts.length == 2 || _zap.amounts.length == 3,
            "!(2 >= amounts.length <= 3)"
        );

        console.log(ctx[0], ctx[1], ctx[2]);
        bool zapHasAmounts = false;
        bool ctxHasAmounts = false;
        for (uint256 i = 0; i < _zap.amounts.length; i++) {
            // Must check we do not unintentionally send ETH
            if (_zap.roots[i] == _ETH_CONSTANT)
                require(msg.value == _zap.amounts[i], "incorrect value");

            if (!ctxHasAmounts && ctx[i] > 0) {
                ctxHasAmounts = true;
            }

            if (_zap.amounts[i] > 0) {
                zapHasAmounts = true;
                if (_zap.roots[i] == _ETH_CONSTANT) {
                    ctx[i] += _zap.amounts[i];
                } else {
                    IERC20(_zap.roots[i]).safeTransferFrom(
                        msg.sender,
                        address(this),
                        _zap.amounts[i]
                    );
                    ctx[i] = IERC20(_zap.roots[i]).balanceOf(address(this));
                }
            }
        }

        if (!zapHasAmounts && !ctxHasAmounts) {
            return 0;
        }

        string memory funcSig = _zap.amounts.length == 2
            ? "add_liquidity(uint256[2],uint256)"
            : "add_liquidity(uint256[3],uint256)";

        console.log(funcSig, ctx[0], ctx[1], ctx[2]);
        // It is necessary to add liquidity to the respective curve pool like this
        // due to the non-standard interface of the function in the curve contracts.
        // Not only is there two variants of fixed length array amount inputs but it is
        // often inconsistent whether return values exist or not
        address(_zap.curvePool).functionCallWithValue(
            abi.encodeWithSelector(bytes4(keccak256(bytes(funcSig))), ctx, 0),
            msg.value
        );

        return _zap.lpToken.balanceOf(address(this));
    }

    function zapCurveIn(
        ZapPtInfo memory _ptInfo,
        ZapCurveLp memory _zap,
        ZapCurveLp[] memory _childZaps
    ) external payable reentrancyGuard notFrozen returns (uint256 ptAmount) {
        uint256[3] memory ctx;
        for (uint256 i = 0; i < _childZaps.length; i++) {
            ctx[_childZaps[i].parentIdx] += _zapCurveLp(_childZaps[i]);
        }

        uint256 baseTokenAmount = _zapCurveLp(_zap, ctx);

        ptAmount = _balancer.swap(
            IVault.SingleSwap({
                poolId: _ptInfo.balancerPoolId,
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(address(_zap.lpToken)),
                assetOut: _ptInfo.principalToken,
                amount: baseTokenAmount,
                userData: "0x00"
            }),
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: _ptInfo.recipient,
                toInternalBalance: false
            }),
            _ptInfo.minPtAmount,
            _ptInfo.deadline
        );
    }
}
