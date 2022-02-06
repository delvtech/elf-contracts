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

    address[] public _3CRV_POOL_TOKENS;
    address internal constant _3CRV_POOL =
        address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    address internal constant _3CRV_POOL_TOKEN =
        address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);

    uint256 internal constant METAPOOL_3CRV_IDX = 1;
    address internal constant _ETH_CONSTANT =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    IVault internal immutable _balancer;

    struct ZapIn {
        address pool;
        address poolToken;
        address[] tokens;
        uint256[] amounts;
        uint256 minAmount;
        bytes32 balancerPoolId;
        address principalToken;
        uint256 deadline;
    }

    struct ZapOut {
        address principalToken;
        uint256 amountPrincipalToken; // amount of pt's
        bytes32 balancerPoolId;
        address pool; // curve pool to change
        address poolToken;
        address token;
        uint256 tokenIdx;
        bool isSigUint256;
        uint256 deadline;
        uint256 minAmountToken;
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

        _3CRV_POOL_TOKENS[0] = address(
            0x6B175474E89094C44Da98b954EedeAC495271d0F
        ); // DAI
        _3CRV_POOL_TOKENS[1] = address(
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        ); // USDC
        _3CRV_POOL_TOKENS[2] = address(
            0xdAC17F958D2ee523a2206206994597C13D831ec7
        ); // USDT
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

    function zapIn(ZapIn memory _zap, PermitData[] memory _permitData)
        external
        payable
        nonReentrant
        notFrozen
        preApproval(_permitData)
        returns (uint256)
    {
        return _zapIn(_zap);
    }

    function Swap3CrvAndZapIn(
        ZapIn memory _zap,
        uint256[] memory _3CrvTokenAmounts,
        PermitData[] memory _permitData
    )
        external
        payable
        nonReentrant
        notFrozen
        preApproval(_permitData)
        returns (uint256)
    {
        _zap.amounts[METAPOOL_3CRV_IDX] += _curvePoolSwapTokensToPoolToken(
            _3CRV_POOL,
            _3CRV_POOL_TOKEN,
            _3CrvTokenAmounts,
            _3CRV_POOL_TOKENS,
            0
        );

        return _zapIn(_zap);
    }

    function _zapIn(ZapIn memory _zap) internal returns (uint256) {
        return
            _balancerSwap(
                _zap.balancerPoolId,
                _zap.poolToken,
                _zap.principalToken,
                _curvePoolSwapTokensToPoolToken(
                    _zap.pool,
                    _zap.poolToken,
                    _zap.amounts,
                    _zap.tokens,
                    0
                ),
                _zap.minAmount,
                msg.sender,
                _zap.deadline
            );
    }

    function zapOut(ZapOut memory _zap, PermitData[] memory _permitData)
        external
        payable
        nonReentrant
        notFrozen
        preApproval(_permitData)
        returns (uint256)
    {
        return _zapOut(_zap, msg.sender);
    }

    function zapOutAndSwap3Crv(
        ZapOut memory _zap,
        uint256 _3CrvTokenIdx,
        PermitData[] memory _permitData
    )
        external
        payable
        nonReentrant
        notFrozen
        preApproval(_permitData)
        returns (uint256)
    {
        // We record and mutate the minAmountToken because we do the curve swap
        // last and want to validate the minAmount of tokens received there
        uint256 minAmountToken = _zap.minAmountToken;
        _zap.minAmountToken = 0;

        return
            _curvePoolSwapPoolTokenToToken(
                _3CRV_POOL,
                _3CRV_POOL_TOKENS[_3CrvTokenIdx],
                _3CrvTokenIdx,
                false,
                msg.sender,
                _zapOut(_zap, address(this)),
                minAmountToken
            );
    }

    function _zapOut(ZapOut memory _zap, address _recipient)
        internal
        returns (uint256)
    {
        IERC20(_zap.principalToken).safeTransferFrom(
            msg.sender,
            address(this),
            _zap.amountPrincipalToken
        );

        uint256 amountPoolToken = _balancerSwap(
            _zap.balancerPoolId,
            _zap.principalToken,
            _zap.poolToken,
            _zap.amountPrincipalToken,
            0, // don't care about intermediary swap, will revert on curve swap
            address(this),
            _zap.deadline
        );

        return
            _curvePoolSwapPoolTokenToToken(
                _zap.pool,
                _zap.token,
                _zap.tokenIdx,
                _zap.isSigUint256,
                _recipient,
                amountPoolToken,
                _zap.minAmountToken
            );
    }

    function _curvePoolSwapTokensToPoolToken(
        address _pool,
        address _poolToken,
        uint256[] memory _amounts,
        address[] memory _tokens,
        uint256 _minAmount
    ) internal returns (uint256) {
        require(
            (_amounts.length == 2 || _amounts.length == 3) &&
                (_tokens.length == _amounts.length),
            "invalid input"
        );

        bool tokenIsEther = false;
        for (uint8 i = 0; i < _amounts.length; i++) {
            if (_tokens[i] == _ETH_CONSTANT) {
                require(msg.value == _amounts[i], "incorrect value");
                tokenIsEther = true;
            } else {
                uint256 beforeAmount = _getBalanceOf(IERC20(_tokens[i]));

                IERC20(_tokens[i]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _amounts[i]
                );
                // This mutates by reference
                _amounts[i] = _getBalanceOf(IERC20(_tokens[i])) - beforeAmount;
            }
        }

        uint256 beforeLpTokenBalance = _getBalanceOf(IERC20(_poolToken));

        if (_amounts.length == 2) {
            ICurvePool(_pool).add_liquidity{
                value: tokenIsEther ? msg.value : 0
            }([_amounts[0], _amounts[1]], _minAmount);
        } else {
            ICurvePool(_pool).add_liquidity{
                value: tokenIsEther ? msg.value : 0
            }([_amounts[0], _amounts[1], _amounts[2]], _minAmount);
        }

        return _getBalanceOf(IERC20(_poolToken)) - beforeLpTokenBalance;
    }

    function _curvePoolSwapPoolTokenToToken(
        address _pool,
        address _token,
        uint256 _tokenIdx,
        bool _isSigUint256,
        address _recipient,
        uint256 _amount,
        uint256 _minAmount
    ) internal returns (uint256 tokenAmountReceived) {
        bool transferToRecipient = address(this) != _recipient;
        bool tokenIsEther = _token == _ETH_CONSTANT;
        uint256 beforeAmount = tokenIsEther
            ? address(this).balance
            : _getBalanceOf(IERC20(_token));

        if (_isSigUint256) {
            ICurvePool(_pool).remove_liquidity_one_coin(
                _amount,
                _tokenIdx,
                _minAmount
            );
        } else {
            ICurvePool(_pool).remove_liquidity_one_coin(
                _amount,
                int128(int256(_tokenIdx)),
                _minAmount
            );
        }

        if (tokenIsEther) {
            tokenAmountReceived = address(this).balance - beforeAmount;
            if (transferToRecipient) {
                payable(_recipient).transfer(tokenAmountReceived);
            }
        } else {
            tokenAmountReceived = _getBalanceOf(IERC20(_token)) - beforeAmount;
            if (transferToRecipient) {
                IERC20(_token).safeTransferFrom(
                    address(this),
                    _recipient,
                    tokenAmountReceived
                );
            }
        }
    }

    function _balancerSwap(
        bytes32 _poolId,
        address _assetIn,
        address _assetOut,
        uint256 _amountAssetIn,
        uint256 _minAmountAssetOut,
        address _recipient,
        uint256 _deadline
    ) internal returns (uint256) {
        return
            _balancer.swap(
                IVault.SingleSwap({
                    poolId: _poolId,
                    kind: IVault.SwapKind.GIVEN_IN,
                    assetIn: IAsset(_assetIn),
                    assetOut: IAsset(_assetOut),
                    amount: _amountAssetIn,
                    userData: "0x00"
                }),
                IVault.FundManagement({
                    sender: address(this),
                    fromInternalBalance: false,
                    recipient: payable(_recipient),
                    toInternalBalance: false
                }),
                _minAmountAssetOut,
                _deadline
            );
    }

    function _getBalanceOf(IERC20 _token) internal view returns (uint256) {
        return _token.balanceOf(address(this));
    }
}
