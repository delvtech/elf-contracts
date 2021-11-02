// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/ICompoundVault.sol";
import "./WrappedPosition.sol";
import "./interfaces/CTokenInterfaces.sol";
import "./interfaces/ComptrollerInterface.sol";

/// @author Element Finance
/// @title Compound Asset Proxy
contract CompoundAssetProxy is WrappedPosition {
    uint8 public immutable underlyingDecimals;
    CTokenInterface public immutable ctoken;
    ComptrollerInterface public immutable comptroller;

    constructor(
        address _ctoken,
        address _comptroller,
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) WrappedPosition(_token, _name, _symbol) {
        ctoken = CTokenInterface(_ctoken);
        comptroller = ComptrollerInterface(_comptroller);
        _token.approve(ctoken, type(uint256).max);
        underlyingDecimals = token.decimals();
        require(
            IERC20(ctoken).decimals() == 8,
            "breaks our assumption in later math"
        );
    }

    /// @notice Makes the actual deposit into the vault
    /// @return Tuple (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        // load balance of contract
        uint256 amount = token.balanceOf(address(this));

        uint256 beforeBalance = ctoken.balanceOf(address(this));

        // deposit into compound
        uint256 mintStatus = ctoken.mint(amount);
        require(mintStatus == 0, "compound mint failed");

        uint256 afterBalance = ctoken.balanceOf(address(this));

        // Compound doesn't return this value, so we calculate it manually

        uint256 share = beforeBalance - afterBalance;
        // Return the amount of shares the user has produced, and the amount of underlying used for it.
        return (share, amount);
    }

    /// @notice Withdraw the number of shares
    /// @param _shares The number of shares to withdraw
    /// @param _destination The address to send the output funds
    // @param _underlyingPerShare The possibly precomputed underlying per share
    /// @return returns the amount of funds freed by doing a withdraw

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
        // TODO: doublecheck this is the right function
        uint256 exchangeRate = ctoken.exchangeRateStored();
        return // multiply _amount by exchange rate & correct for decimals
        ((_amount * exchangeRate) / (10**(26 - underlyingDecimals)));
    }
}
