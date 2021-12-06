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

    receive() external payable {}

    bool private _noReentry = false;

    modifier reentrancyGuard() {
        require(!_noReentry);
        _noReentry = true;
        _;
        _noReentry = false;
    }

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

    struct ZapCurveLpIn {
        address curvePool;
        IERC20 lpToken;
        uint256[] amounts;
        address[] roots;
        uint256 parentIdx;
        bytes4 funcSig; // add_liquidity
    }
    struct ZapInInfo {
        bytes32 balancerPoolId;
        address recipient;
        IAsset principalToken;
        uint256 minPtAmount;
        uint256 deadline;
    }

    function _zapCurveLpIn(ZapCurveLpIn memory _zap)
        internal
        returns (uint256)
    {
        uint256[3] memory ctx;
        return _zapCurveLpIn(_zap, ctx);
    }

    // Given that we call the curve add liquidity function through a low-level
    // call, we can utilise a fixed-length array of length 3 as our input context
    // "bucket". In the event where the target curve pool contract expects an
    // array of length 2, we can still utilise the "bucket" where the last index is
    // disregarded.
    function _zapCurveLpIn(ZapCurveLpIn memory _zap, uint256[3] memory ctx)
        internal
        returns (uint256)
    {
        require(
            _zap.amounts.length == 2 || _zap.amounts.length == 3,
            "!(2 >= amounts.length <= 3)"
        );

        bool zapHasAmounts = false;
        bool ctxHasAmounts = false;
        for (uint8 i = 0; i < _zap.amounts.length; i++) {
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
        // It is necessary to add liquidity to the respective curve pool like this
        // due to the non-standard interface of the function in the curve contracts.
        // Not only is there two variants of fixed length array amount inputs but it is
        // often inconsistent whether return values exist or not
        address(_zap.curvePool).functionCallWithValue(
            abi.encodeWithSelector(_zap.funcSig, ctx, 0),
            msg.value
        );

        return _zap.lpToken.balanceOf(address(this));
    }

    function zapIn(
        ZapInInfo memory _info,
        ZapCurveLpIn memory _zap,
        ZapCurveLpIn[] memory _childZaps
    ) external payable reentrancyGuard notFrozen returns (uint256 ptAmount) {
        uint256[3] memory ctx;
        for (uint8 i = 0; i < _childZaps.length; i++) {
            uint256 _amount = _zapCurveLpIn(_childZaps[i]);
            ctx[_childZaps[i].parentIdx] += _amount;
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

    struct ZapCurveLpOut {
        address curvePool;
        IERC20 lpToken;
        int128 rootTokenIdx;
        address rootToken;
        bytes4 funcSig; // remove_liquidity_one_coin
    }

    struct ZapOutInfo {
        bytes32 balancerPoolId;
        IAsset principalToken;
        uint256 principalTokenAmount;
        address payable recipient;
        uint256 minRootTokenAmount;
        uint256 deadline;
        bool targetNeedsChildZap;
    }

    function _zapCurveLpOut(
        ZapCurveLpOut memory _zap,
        uint256 _lpTokenAmount,
        uint256 _minRootTokenAmount,
        address payable _recipient
    ) internal returns (uint256 rootAmount) {
        bool transferToTarget = address(this) != _recipient;
        address(_zap.curvePool).functionCall(
            abi.encodeWithSelector(
                _zap.funcSig,
                _lpTokenAmount,
                _zap.rootTokenIdx,
                _minRootTokenAmount
            )
        );

        if (_zap.rootToken == _ETH_CONSTANT) {
            rootAmount = address(this).balance;
            // if address does not equal this contract we send funds to recipient
            if (transferToTarget) {
                _recipient.transfer(rootAmount);
            }
        } else {
            rootAmount = IERC20(_zap.rootToken).balanceOf(address(this));
            if (transferToTarget) {
                IERC20(_zap.rootToken).safeTransferFrom(
                    address(this),
                    _recipient,
                    rootAmount
                );
            }
        }
    }

    function zapOut(
        ZapOutInfo memory _info,
        ZapCurveLpOut memory _zap,
        ZapCurveLpOut memory _childZap
    ) external payable reentrancyGuard notFrozen returns (uint256 amount) {
        // First, principalTokenAmount of principal tokens transferred
        // from sender to this contract
        IERC20(address(_info.principalToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _info.principalTokenAmount
        );

        // Then, contract swaps the principal tokens for an
        // unspecified amount of baseTokens on balancer
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

        // If the target token is a root token of a meta pool, two curve swaps
        // are necessary.
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
}
