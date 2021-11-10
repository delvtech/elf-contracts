// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "hardhat/console.sol";

import "../libraries/Authorizable.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ITranche.sol";

interface ICrvAddLiqTwo {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount)
        external
        payable
        returns (uint256);
}

interface ICrvAddLiqThree {
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount)
        external
        payable
        returns (uint256);
}

interface ICurveFi is ICrvAddLiqTwo, ICrvAddLiqThree {
    function lp_token() external view returns (address);

    function coins(uint256 idx) external view returns (address);
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
        IVault __balancer,
        address[] tokens
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

    // function setApprovalFor(address[] tokens, address[] crvPools) external onlyAuthorized {
    //     // maxApproval for each
    // }

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

    // struct ZapCurveLp {
    //     ICurveFi curvePool;
    //     uint256[] amounts;
    //     address[] tokens;
    // }

    struct ZapCurveIn {
        ICurveFi curvePool;
        uint256[] amounts;
        address[] tokens;
        bytes32 balancerPoolId;
        address payable recipient;
        address principalToken;
        uint256 minPtAmount;
        uint256 deadline;
    }

    function _zapCurveInThree(ZapCurveIn memory _zap)
        internal
        returns (uint256 baseTokenAmount)
    {
        uint256[3] memory crvInputCtx;

        bool validAmountsFlag = false;
        for (uint256 i = 0; i < _zap.amounts.length; i++) {
            require(
                _zap.curvePool.coins(i) == _zap.tokens[i],
                "incorrect token address"
            );
            if (_zap.tokens[i] == _ETH_CONSTANT) {
                require(
                    msg.value == _zap.amounts[i],
                    "incorrect amount provided"
                );
            } else {
                IERC20(_zap.tokens[i]).approve(
                    address(_zap.curvePool),
                    _zap.amounts[i]
                );
            }

            if (!validAmountsFlag && _zap.amounts[i] > 0) {
                validAmountsFlag = true;
            }
            crvInputCtx[i] = _zap.amounts[i];
        }

        baseTokenAmount = _zap.curvePool.add_liquidity{ value: msg.value }(
            crvInputCtx,
            0
        );
    }

    function _zapCurveInTwo(ZapCurveIn memory _zap)
        internal
        returns (uint256 baseTokenAmount)
    {
        uint256[2] memory crvInputCtx;

        bool validAmountsFlag = false;
        for (uint256 i = 0; i < _zap.amounts.length; i++) {
            require(
                _zap.curvePool.coins(i) == _zap.tokens[i],
                "incorrect token address"
            );
            if (_zap.tokens[i] == _ETH_CONSTANT) {
                require(
                    msg.value == _zap.amounts[i],
                    "incorrect amount provided"
                );
            } else {
                uint256 allowance = IERC20(_zap.tokens[i]).allowance(
                    msg.sender,
                    address(this)
                );
                console.log("allowance: %s", allowance);
                require(allowance >= _zap.amounts[i], "allowance not set");
                IERC20(_zap.tokens[i]).transferFrom(
                    msg.sender,
                    address(this),
                    _zap.amounts[i]
                );

                IERC20(_zap.tokens[i]).approve(
                    address(_zap.curvePool),
                    IERC20(_zap.tokens[i]).balanceOf(address(this))
                );

                console.log(
                    "%s :: %s",
                    _zap.tokens[i],
                    IERC20(_zap.tokens[i]).balanceOf(address(this))
                );
            }

            if (!validAmountsFlag && _zap.amounts[i] > 0) {
                validAmountsFlag = true;
            }
            crvInputCtx[i] = _zap.amounts[i];
        }

        require(validAmountsFlag, "invalid amounts");

        console.log("curveInputs: %s %s", crvInputCtx[0], crvInputCtx[1]);
        baseTokenAmount = _zap.curvePool.add_liquidity{ value: msg.value }(
            crvInputCtx,
            0
        );
    }

    // function processCrvLp(ZapLpIn crv) internal {
    //      if (_zap.amounts.length == 2) {
    //         baseTokenAmount = _zapCurveInTwo(_zap);
    //     } else if (_zap.amounts.length == 3) {
    //         baseTokenAmount = _zapCurveInThree(_zap);
    //     } else {
    //         revert("!(2 >= numAmounts <= 3)");
    //     }

    // }

    // function zapCurveIn(ZapLpIn f, hasSecondLayer, ZapLpIn g)
    //     external
    //     payable
    //     reentrancyGuard
    //     notFrozen
    //     returns (uint256 ptAmount)
    // {

    function zapCurveIn(ZapCurveIn _zap)
        external
        payable
        reentrancyGuard
        notFrozen
        returns (uint256 ptAmount)
    {
        // uint256 baseTokenAmount;
        // if (hasSecondLayer) {
        //     process(g)
        // }

        // process(f)

        if (_zap.amounts.length == 2) {
            baseTokenAmount = _zapCurveInTwo(_zap);
        } else if (_zap.amounts.length == 3) {
            baseTokenAmount = _zapCurveInThree(_zap);
        } else {
            revert("!(2 >= numAmounts <= 3)");
        }
        console.log(baseTokenAmount);

        // uint256[2] memory crvPoolInputCtx;
        // crvPoolInputCtx[_zap.inputTokenIdx] = _amount;
        // uint256 baseTokenAmount;
        // if (address(_zap.inputToken) == _ETH_CONSTANT) {
        //     require(msg.value == _amount, "Incorrect amount provided");
        //     // don't enforce a minimum lp out, we can enforce a minimum PT swap output later
        //     baseTokenAmount = _zap.crvPool.add_liquidity{ value: msg.value }(
        //         crvPoolInputCtx,
        //         0
        //     );
        // } else {
        //     require(msg.value == 0, "Non payable");
        //     // don't enforce a minimum lp out, we can enforce a minimum PT swap output later
        //     baseTokenAmount = _zap.crvPool.add_liquidity(crvPoolInputCtx, 0);
        // }
        // _zap.baseToken.approve(address(_balancer), baseTokenAmount);
        // IVault.SingleSwap memory sswap = IVault.SingleSwap({
        //     poolId: _zap.balancerPoolId,
        //     kind: IVault.SwapKind.GIVEN_IN,
        //     assetIn: IAsset(address(_zap.baseToken)),
        //     assetOut: IAsset(_zap.principalToken),
        //     amount: baseTokenAmount,
        //     userData: "0x00"
        // });
        // IVault.FundManagement memory fmgmt = IVault.FundManagement({
        //     sender: address(this),
        //     fromInternalBalance: false,
        //     recipient: _recipient,
        //     toInternalBalance: false
        // });
        // ptAmount = _balancer.swap(sswap, fmgmt, _minPtAmount, _deadline);
    }
}
