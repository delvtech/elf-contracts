// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "hardhat/console.sol";

import "../libraries/Authorizable.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ITranche.sol";

interface ICurveFi {
    function lp_token() external view returns (address);

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external
        payable
        returns (uint256);
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

    /// @param __trancheFactory Address of the TrancheFactory contract
    /// @param __trancheBytecodeHash Hash of the Tranche bytecode.
    constructor(address __trancheFactory, bytes32 __trancheBytecodeHash)
        Authorizable()
    {
        _authorize(msg.sender);
        _trancheFactory = __trancheFactory;
        _trancheBytecodeHash = __trancheBytecodeHash;
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

    struct ZapIn {
        // Address of inputToken
        address inputToken;
        // Index of the inputToken in curve pool
        uint256 inputTokenIdx;
        // Curve Pool we will single-side lp to get baseToken
        ICurveFi crvPool;
        // Address of the baseToken necessary to
        // enter yield pool, e.g crvSTETH
        address baseToken;
        // Id of convergent curve pool for baseToken/principal token pairing
        bytes32 balancerPoolId;
        // Address of balancer vault
        IVault balancerVault;
        // Address of ptToken
        address principalToken;
    }

    function zapIn(
        ZapIn memory _zap,
        uint256 _amount,
        address payable _recipient,
        uint256 _minPtAmount,
        uint256 _deadline
    ) external payable reentrancyGuard notFrozen returns (uint256 ptAmount) {
        require(_amount != 0, "0 amount");

        uint256[2] memory crvPoolInputCtx;
        crvPoolInputCtx[_zap.inputTokenIdx] = _amount;

        uint256 baseTokenAmount;
        if (address(_zap.inputToken) == _ETH_CONSTANT) {
            require(msg.value == _amount, "Incorrect amount provided");
            // don't enforce a minimum lp out, we can enforce a minimum PT swap output later
            baseTokenAmount = _zap.crvPool.add_liquidity{ value: msg.value }(
                crvPoolInputCtx,
                0
            );
        } else {
            require(msg.value == 0, "Non payable");
            // don't enforce a minimum lp out, we can enforce a minimum PT swap output later
            baseTokenAmount = _zap.crvPool.add_liquidity(crvPoolInputCtx, 0);
        }

        console.log(
            "InputToken: %s -> BaseToken: %s",
            _amount,
            baseTokenAmount
        );
        console.log("Balancer Vault: %s", address(_zap.balancerVault));
        (address x, IVault.PoolSpecialization y) = _zap.balancerVault.getPool(
            _zap.balancerPoolId
        );
        console.log("CCPool: %s", x);

        // IVault.SingleSwap memory sswap = IVault.SingleSwap({
        //     poolId: _zap.balancerPoolId,
        //     kind: IVault.SwapKind.GIVEN_IN,
        //     assetIn: IAsset(_zap.baseToken),
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

        // ptAmount = _zap.balancerVault.swap(sswap, fmgmt, _minPtAmount, _deadline);
    }
}
