// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "hardhat/console.sol";

import "../libraries/Authorizable.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ITranche.sol";

interface ICurveFiTwo {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount)
        external
        payable
        returns (uint256);

    function calc_token_amount(uint256[2] memory amounts, bool is_deposit)
        external
        view
        returns (uint256);
}

interface ICurveFiThree {
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount)
        external
        payable
        returns (uint256);

    function calc_token_amount(uint256[3] memory amounts, bool is_deposit)
        external
        view
        returns (uint256);
}

interface ICurveFi is ICurveFiTwo, ICurveFiThree {
    function lp_token() external view returns (address);
}

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

contract ZapTokenToPt is Authorizable {
    // Store the accessibility state of the contract
    bool public isFrozen = false;
    // Tranche factory address for Tranche contract address derivation
    address internal immutable _trancheFactory;
    // Tranche bytecode hash for Tranche contract address derivation.
    // This is constant as long as Tranche does not implement non-constant constructor arguments.
    bytes32 internal immutable _trancheBytecodeHash;

    address internal constant _ETH_CONSTANT =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    IVault internal immutable _balancer;

    /// @param __trancheFactory Address of the TrancheFactory contract
    /// @param __trancheBytecodeHash Hash of the Tranche bytecode.
    constructor(
        address __trancheFactory,
        bytes32 __trancheBytecodeHash,
        IVault __balancer
    ) Authorizable() {
        _authorize(msg.sender);
        _trancheFactory = __trancheFactory;
        _trancheBytecodeHash = __trancheBytecodeHash;
        _balancer = __balancer;
    }

    bool private _noReentry = false;

    /// @dev Prevents contract reentrancy.
    /// @notice reentrancyGuarded functions should be external
    /// since they don't support calling themselves
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
            IERC20(tokens[i]).approve(spenders[i], type(uint256).max);
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
        ICurveFi curvePool;
        uint256[] amounts;
        address[] roots;
    }

    struct ZapPtInfo {
        bytes32 balancerPoolId;
        address payable recipient;
        IAsset principalToken;
        uint256 minPtAmount;
        uint256 deadline;
    }

    function _zapTwoRootsToCurveLp(ZapCurveLp memory _zap)
        internal
        returns (uint256 crvLpAmount)
    {
        uint256[2] memory ctx;
        for (uint256 i = 0; i < _zap.amounts.length; i++) {
            if (_zap.roots[i] == _ETH_CONSTANT) {
                require(msg.value == _zap.amounts[i], "incorrect value");
                ctx[i] = _zap.amounts[i];
            } else {
                IERC20(_zap.roots[i]).transferFrom(
                    msg.sender,
                    address(this),
                    _zap.amounts[i]
                );
                ctx[i] = IERC20(_zap.roots[i]).balanceOf(address(this));
            }
        }
        crvLpAmount = _zap.curvePool.add_liquidity{ value: msg.value }(ctx, 0);
    }

    function _zapThreeRootsToCurveLp(ZapCurveLp memory _zap)
        internal
        returns (uint256 crvLpAmount)
    {
        uint256[3] memory ctx;
        for (uint256 i = 0; i < _zap.amounts.length; i++) {
            if (_zap.roots[i] == _ETH_CONSTANT) {
                require(msg.value == _zap.amounts[i], "incorrect value");
                ctx[i] = _zap.amounts[i];
            } else {
                IERC20(_zap.roots[i]).transferFrom(
                    msg.sender,
                    address(this),
                    _zap.amounts[i]
                );
                ctx[i] = IERC20(_zap.roots[i]).balanceOf(address(this));
            }
        }
        crvLpAmount = _zap.curvePool.add_liquidity{ value: msg.value }(ctx, 0);
    }

    function _zapCurveLp(ZapCurveLp memory _zap)
        internal
        returns (uint256 crvLpAmount)
    {
        if (_zap.amounts.length == 2) {
            crvLpAmount = _zapTwoRootsToCurveLp(_zap);
        } else if (_zap.amounts.length == 3) {
            crvLpAmount = _zapThreeRootsToCurveLp(_zap);
        } else {
            revert("!(2 >= amounts.length <= 3)");
        }
    }

    function zapCurveIn(
        ZapPtInfo memory _ptInfo,
        ZapCurveLp memory _zap,
        ZapCurveLp[] memory _rootZaps,
        uint256[] _rootZapsIndexes
    ) external payable reentrancyGuard notFrozen returns (uint256 ptAmount) {
        for (uint256 i = 0; i < _rootZaps.length; i++) {
            _zap.amounts[_rootZapsIndexes[i]] += _zapCurveLp(_rootZaps[i]);
        }

        uint256 baseTokenAmount = _zapCurveLp(_zap);
        IERC20 baseToken = IERC20(_zap.curvePool.lp_token());

        ptAmount = _balancer.swap(
            IVault.SingleSwap({
                poolId: _ptInfo.balancerPoolId,
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(address(baseToken)),
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
