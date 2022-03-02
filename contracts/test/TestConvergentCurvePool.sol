// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../ConvergentCurvePool.sol";
import "../balancer-core-v2/lib/math/FixedPoint.sol";

contract TestConvergentCurvePool is ConvergentCurvePool {
    using FixedPoint for uint256;

    constructor(
        IERC20 _underlying,
        IERC20 _bond,
        uint256 _expiration,
        uint256 _unitSeconds,
        IVault vault,
        uint256 _percentFee,
        address _governance,
        string memory name,
        string memory symbol
    )
        ConvergentCurvePool(
            _underlying,
            _bond,
            _expiration,
            _unitSeconds,
            vault,
            _percentFee,
            _percentFee,
            _governance,
            name,
            symbol,
            _governance
        )
    {} // solhint-disable-line no-empty-blocks

    event UIntReturn(uint256 data);

    // Allows tests to burn LP tokens directly
    function burnLP(
        uint256 lpBurn,
        uint256[] memory currentBalances,
        address source
    ) public {
        uint256[] memory outputs = _burnLP(lpBurn, currentBalances, source);
        // We use this to return because returndata from state changing tx isn't easily accessible.
        emit UIntReturn(outputs[baseIndex]);
        emit UIntReturn(outputs[bondIndex]);
    }

    // Allows tests to mint LP tokens directly
    function mintLP(
        uint256 inputUnderlying,
        uint256 inputBond,
        uint256[] memory currentBalances,
        address recipient
    ) public {
        uint256[] memory amountsIn = _mintLP(
            inputUnderlying,
            inputBond,
            currentBalances,
            recipient
        );
        // We use this to return because returndata from state changing tx isn't easily accessible.
        emit UIntReturn(amountsIn[baseIndex]);
        emit UIntReturn(amountsIn[bondIndex]);
    }

    // Allows tests to access the trade fee calculator
    function assignTradeFee(
        uint256 amountIn,
        uint256 amountOut,
        IERC20 outputToken,
        bool isInputTrade
    ) public {
        IERC20 quoteToken;
        if (outputToken == underlying) {
            amountIn = _tokenToFixed(amountIn, bond);
            amountOut = _tokenToFixed(amountOut, underlying);
            quoteToken = isInputTrade ? bond : underlying;
        } else {
            amountIn = _tokenToFixed(amountIn, underlying);
            amountOut = _tokenToFixed(amountOut, bond);
            quoteToken = isInputTrade ? underlying : bond;
        }
        uint256 newQuote = _assignTradeFee(
            amountIn,
            amountOut,
            outputToken,
            isInputTrade
        );
        emit UIntReturn(_fixedToToken(newQuote, quoteToken));
    }

    // Allows tests to specify fees without making trades
    function setFees(uint120 amountUnderlying, uint120 amountBond) public {
        feesUnderlying = amountUnderlying;
        feesBond = amountBond;
    }

    function setLPBalance(address who, uint256 what) public {
        uint256 current = this.balanceOf(who);
        if (what > current) {
            _mintPoolTokens(who, what - current);
        } else if (what < current) {
            _burnPoolTokens(who, current - what);
        }
    }

    // Public interface to test '_getYieldExponent'
    function getYieldExponent() public view returns (uint256) {
        return _getYieldExponent();
    }

    uint256 public time;

    function swapSimulation(
        IPoolSwapStructs.SwapRequest memory request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut,
        uint256 _time,
        uint256 expectedPrice,
        uint256 totalSupply
    ) public returns (uint256) {
        time = _time;
        // We now set the total supply
        setLPBalance(request.from, totalSupply);
        uint256 quote = onSwap(
            request,
            currentBalanceTokenIn,
            currentBalanceTokenOut
        );
        time = 0;
        if (expectedPrice != 0) {
            return
                (quote > expectedPrice)
                    ? quote - expectedPrice
                    : expectedPrice - quote;
        } else {
            return quote;
        }
    }

    // Allows the error measurement test to set the time
    function _getYieldExponent() internal view override returns (uint256) {
        // Load the stored time if it's set use that instead
        if (time > 0) {
            return uint256(FixedPoint.ONE).sub(time);
        } else {
            return super._getYieldExponent();
        }
    }

    // Public interface to test '_tokenToFixed'
    function tokenToFixed(uint256 amount, IERC20 token)
        public
        view
        returns (uint256)
    {
        return _tokenToFixed(amount, token);
    }

    // Public interface to test '_fixedToToken'
    function fixedToToken(uint256 amount, IERC20 token)
        public
        view
        returns (uint256)
    {
        return _fixedToToken(amount, token);
    }

    // Public interface to test '_normalize'
    function normalize(
        uint256 amount,
        uint8 decimalsBefore,
        uint8 decimalsAfter
    ) public pure returns (uint256) {
        return _normalize(amount, decimalsBefore, decimalsAfter);
    }
}
