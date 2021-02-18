pragma solidity >=0.7.1;
pragma experimental ABIEncoderV2;

import "../balancer/YieldPool.sol";
import "../balancer/FixedPoint.sol";

contract YieldPoolTest is YieldCurvePool {
    using FixedPoint for uint256;

    constructor(
        IERC20 _underlying,
        IERC20 _bond,
        uint256 _expiration,
        uint256 _unit_seconds,
        IVault vault,
        uint256 _percentFee,
        address _governance,
        string memory name,
        string memory symbol
    )
        YieldCurvePool(
            _underlying,
            _bond,
            _expiration,
            _unit_seconds,
            vault,
            _percentFee,
            _governance,
            name,
            symbol
        )
    {}

    event uintReturn(uint256 data);

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
        emit uintReturn(releasedUnderlying);
        emit uintReturn(releasedBond);
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
        emit uintReturn(usedUnderlying);
        emit uintReturn(usedBond);
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
        emit uintReturn(newQuote);
    }

    // Allows tests to specify fees without making trades
    function setFees(uint128 amountUnderlying, uint128 amountBond) public {
        feesUnderlying = amountUnderlying;
        feesBond = amountBond;
    }

    function setLPBalance(address who, uint256 what) public {
        uint256 current = balanceOf(who);
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
    ) public view returns (uint256) {
        return _normalize(amount, decimalsBefore, decimalsAfter);
    }

    // Trade estimator which also takes and stores a time override variable
    // if expectedPrice is nonzero it returns the delta in price instead of
    // the quote
    function quoteInGivenOutSimulation(
        IPoolQuoteStructs.QuoteRequestGivenOut calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut,
        uint256 _time,
        uint256 expectedPrice
    ) external returns (uint256) {
        time = _time;
        uint256 quote = quoteInGivenOut(
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
        IPoolQuoteStructs.QuoteRequestGivenIn calldata request,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut,
        uint256 _time,
        uint256 expectedPrice
    ) external returns (uint256) {
        time = _time;
        uint256 quote = quoteOutGivenIn(
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

    uint256 time;

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
