// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
            symbol
        )
    {} // solhint-disable-line no-empty-blocks

    event UIntReturn(uint256 data);

    // Allows tests to burn LP tokens directly
    function burnLP(
        uint256 outputUnderlying,
        uint256 outputBond,
        uint256[] memory currentBalances,
        address source
    ) public {
        (uint256 releasedUnderlying, uint256 releasedBond) = _burnLP(
            outputUnderlying,
            outputBond,
            currentBalances,
            source
        );
        // We use this to return because returndata from state changing tx isn't easily accessible.
        emit UIntReturn(releasedUnderlying);
        emit UIntReturn(releasedBond);
    }

    // Allows tests to mint LP tokens directly
    function mintLP(
        uint256 inputUnderlying,
        uint256 inputBond,
        uint256[] memory currentBalances,
        address recipient
    ) public {
        (uint256 usedUnderlying, uint256 usedBond) = _mintLP(
            inputUnderlying,
            inputBond,
            currentBalances,
            recipient
        );
        // We use this to return because returndata from state changing tx isn't easily accessible.
        emit UIntReturn(usedUnderlying);
        emit UIntReturn(usedBond);
    }

    // Allows tests to access mint gov LP
    function mintGovLP(uint256[] memory currentReserves) public {
        _mintGovernanceLP(currentReserves);
    }

    // Allows tests to access the trade fee calculator
    function assignTradeFee(
        uint256 amountIn,
        uint256 amountOut,
        IERC20 outputToken,
        bool isInputTrade
    ) public {
        uint256 newQuote = _assignTradeFee(
            amountIn,
            amountOut,
            outputToken,
            isInputTrade
        );
        emit UIntReturn(newQuote);
    }

    // Allows tests to specify fees without making trades
    function setFees(uint128 amountUnderlying, uint128 amountBond) public {
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

    // Trade estimator which also takes and stores a time override variable
    // if expectedPrice is nonzero it returns the delta in price instead of
    // the quote
    function quoteInGivenOutSimulation(
        IPoolSwapStructs.SwapRequestGivenOut calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut,
        uint256 _time,
        uint256 expectedPrice,
        uint256 totalSupply
    ) external returns (uint256) {
        time = _time;
        // We now set the total supply
        setLPBalance(request.from, totalSupply);
        uint256 quote = onSwapGivenOut(
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

    // Trade estimator which also takes and stores a time override variable
    // if expectedPrice is nonzero it returns the delta in price instead of
    // the quote
    function quoteOutGivenInSimulation(
        IPoolSwapStructs.SwapRequestGivenIn calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut,
        uint256 _time,
        uint256 expectedPrice,
        uint256 totalSupply
    ) external returns (uint256) {
        time = _time;
        // We now set the total supply
        setLPBalance(request.from, totalSupply);
        uint256 quote = onSwapGivenIn(
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

    uint256 public time;

    // Allows the error measurement test to set the time
    function _getYieldExponent() internal override view returns (uint256) {
        // Load the stored time if it's set use that instead
        if (time > 0) {
            return uint256(FixedPoint.ONE).sub(time);
        } else {
            return super._getYieldExponent();
        }
    }
}
