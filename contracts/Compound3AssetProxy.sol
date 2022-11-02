// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0;

import "./interfaces/IERC20.sol";
import "./WrappedPosition.sol";
import "./interfaces/external/CometMainInterface.sol";
import "./libraries/Authorizable.sol";

/// @author Element Finance
/// @title Compound Asset Proxy
contract Compound3AssetProxy is WrappedPosition, Authorizable {
    uint8 public immutable underlyingDecimals;
    // The comet contract
    CometMainInterface public immutable comet;
    // The comet reward contract
    CometRewards public immutable cometRewards;
    // cTokens issued
    uint256 public yieldSharesIssued;

    /// @notice Constructs this contract and stores needed data
    /// @param _comet The underlying ctoken
    /// @param _cometRewards The Compound rewards contract
    /// @param _token The underlying token
    /// @param _name The name of the token created
    /// @param _symbol The symbol of the token created
    /// @param _owner The contract owner who is authorized to collect rewards
    constructor(
        address _comet,
        address _cometRewards,
        IERC20 _token,
        string memory _name,
        string memory _symbol,
        address _owner
    ) WrappedPosition(_token, _name, _symbol) {
        _authorize(_owner);
        // Authorize the contract owner
        setOwner(_owner);

        comet = CometMainInterface(_comet);
        cometRewards = CometRewards(_cometRewards);
        // Set approval for the proxy
        _token.approve(_comet, type(uint256).max);
        underlyingDecimals = _token.decimals();

        // require(underlyingDecimals == comet.decimals(), "inconsistent decimals");
        // // We must assume the ctoken has 8 decimals to make the correct calculation for exchangeRate
        // require(
        //     IERC20(_comet).decimals() == 8,
        //     "breaks our assumption in exchange rate"
        // );

        // Check that the underlying token is the same as ctoken's underlying
        require(address(_token) == CometMainInterface(_comet).baseToken());
    }

    /// @notice Makes the actual ctoken deposit
    /// @return Tuple (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        // Load balance of contract
        uint256 depositAmount = token.balanceOf(address(this));
        // cToken balance before depositing
        uint256 beforeBalance = comet.balanceOf(address(this));
        // Deposit into compound
        // 'token' is an immutable in WrappedPosition
        comet.supply(address(token), depositAmount);
        // upon depositing, comet mints cToken == depositAmount. Balance of cToken increases as it accrues interest.
        // We track number of tokens we have minted at the deposit call.
        yieldSharesIssued += depositAmount;
        // Get ctoken balance after minting
        uint256 afterBalance = comet.balanceOf(address(this));
        // Calculate ctoken shares minted - this should vbe equal to depositAmount.
        uint256 shares = afterBalance - beforeBalance;
        // Return the amount of shares the user has produced and the amount of underlying used for it.
        return (shares, depositAmount);
    }

    /// @notice Withdraw the number of shares
    /// @param _shares The number of shares to withdraw
    /// @param _destination The address to send the output funds
    // @param _underlyingPerShare The possibly precomputed underlying per share
    /// @return Amount of funds freed by doing a withdraw
    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256
    ) internal override returns (uint256) {
        // comet doesn't return how much was withdrawn, so we get the balance before and after withdrawal.
        // 'token' is an immutable in WrappedPosition
        uint256 beforeBalance = token.balanceOf(address(this));
        // withdraw from comet
        comet.withdraw(address(token), _shares);
        // Get underlying balance after withdrawing
        uint256 afterBalance = token.balanceOf(address(this));
        // Calculate the amount of funds that were freed
        // cTokens increase with balance. So amountReceived is close to _shares.
        uint256 amountReceived = afterBalance - beforeBalance;
        // Transfer the underlying to the destination
        token.transfer(_destination, amountReceived);
        // Return the amount of underlying
        return amountReceived;
    }

    /// @notice Get the underlying amount of tokens per shares given
    /// @param _amount The amount of shares you want to know the value of
    /// @return Value of shares in underlying token
    function _underlying(uint256 _amount)
        internal
        view
        override
        returns (uint256)
    {
        return yieldSharesAsUnderlying(_amount);
    }

    /// @notice Calculates the yieldShare value for an amount of underlying
    /// @return yieldShares `YieldShares` is an internal and inferred constant
    ///         time representation of a depositors claim of a growing pool of
    ///         deposited underlying by this contract in the Compound protocol.
    ///         The rationale to do so is due to Compounds non-constant
    ///         representation of "share" balances being directly the underlying
    ///         deposited + the interest accrued. Integrations with this
    ///         protocol must represent shares in a fixed amount so we infer
    ///         this artificially using `yieldSharesIssued`
    function underlyingAsYieldShares(uint256 underlying)
        public
        view
        returns (uint256 yieldShares)
    {
        yieldShares =
            (yieldSharesIssued * underlying) /
            comet.balanceOf(address(this));
    }

    /// @notice Calculates the underlying value for an amount of yieldShares
    /// @return underlying The token yield is denominated in
    function yieldSharesAsUnderlying(uint256 yieldShares)
        public
        view
        returns (uint256 underlying)
    {
        underlying =
            (comet.balanceOf(address(this)) * yieldShares) /
            yieldSharesIssued;
    }

    /// @notice Collect the comp rewards accrued
    /// @param _destination The address to send the rewards to
    function collectRewards(address _destination) external onlyAuthorized {
        cometRewards.claimTo(address(comet), address(this), _destination, true);
    }
}
