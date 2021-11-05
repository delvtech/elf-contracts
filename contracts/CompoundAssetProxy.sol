// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.5.16;

import "./interfaces/IERC20.sol";
import "./WrappedPosition.sol";
import "./interfaces/CTokenInterfaces.sol";
import "./interfaces/ComptrollerInterface.sol";
import "./libraries/Authorizable.sol";

/// @author Element Finance
/// @title Compound Asset Proxy
contract CompoundAssetProxy is WrappedPosition, Authorizable {
    uint8 public immutable underlyingDecimals;
    CErc20Interface public immutable ctoken;
    ComptrollerInterface public immutable comptroller;

    /// @notice Constructs this contract and stores needed data
    /// @param _ctoken The compound ctoken contract
    /// @param _comptroller The compound comptroller
    /// @param _token The underlying token
    /// @param _name The name of the token created
    /// @param _symbol The symbol of the token created
    constructor(
        address _ctoken,
        address _comptroller,
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) WrappedPosition(_token, _name, _symbol) {
        ctoken = CErc20Interface(_ctoken);
        comptroller = ComptrollerInterface(_comptroller);
        _token.approve(_ctoken, type(uint256).max);
        underlyingDecimals = _token.decimals();
        // we must assume the ctoken has 8 decimals to make the correct calculation for exchangeRate
        require(
            IERC20(_ctoken).decimals() == 8,
            "breaks our assumption in exchange rate"
        );
    }

    /// @notice Makes the actual ctoken deposit
    /// @return Tuple (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        // load balance of contract
        uint256 amount = token.balanceOf(address(this));

        uint256 beforeBalance = ctoken.balanceOfUnderlying(address(this));

        // deposit into compound
        uint256 mintStatus = ctoken.mint(amount);
        require(mintStatus == 0, "compound mint failed");

        uint256 afterBalance = ctoken.balanceOfUnderlying(address(this));

        // Compound doesn't return this value, so we calculate it manually
        uint256 share = beforeBalance - afterBalance;
        // Return the amount of shares the user has produced, and the amount of underlying used for it.
        return (share, amount);
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
        uint256 beforeBalance = token.balanceOf(address(this));

        // do the withdraw
        uint256 redeemStatus = ctoken.redeem(_shares);
        require(redeemStatus == 0, "compound mint failed");

        uint256 afterBalance = token.balanceOf(address(this));
        uint256 amountReceived = afterBalance - beforeBalance;
        // Transfer the underlying to the destination 'token' is an immutable in WrappedPosition
        token.transfer(_destination, amountReceived);

        // Return the amount of underlying
        return amountReceived;
    }

    /// @notice Get the underlying amount of tokens per shares given
    /// @param _amount The amount of shares you want to know the value of
    /// @return Value of shares in underlying token
    function _underlying(uint256 _amount)
        internal
        override
        view
        returns (uint256)
    {
        // load exchange rate
        uint256 exchangeRate = ctoken.exchangeRateStored();

        // multiply _amount by exchange rate & correct for decimals
        // we assume 8 decimals in the ctoken + 18 point decimal fix = 26
        return ((_amount * exchangeRate) / (10**(26 - underlyingDecimals)));
    }

    /// @notice Collect the comp rewards accrued
    /// @param _destination The address to send the rewards to
    function collectRewards(address _destination) external onlyAuthorized() {
        // collect rewards
        uint256 beforeBalance = ctoken.balanceOfUnderlying(address(this));

        // set up input params
        address[] memory holder = new address[](1);
        holder[1] = address(this);
        CErc20Interface[] memory cTokens = new CErc20Interface[](1);
        cTokens[1] = ctoken;

        comptroller.claimComp(holder, cTokens, true, true);
        uint256 afterBalance = ctoken.balanceOfUnderlying(address(this));
        uint256 rewardAmount = afterBalance - beforeBalance;

        // send those to an address
        token.transfer(_destination, rewardAmount);
    }
}
