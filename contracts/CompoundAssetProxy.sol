// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/ICompoundVault.sol";
import "./WrappedPosition.sol";

/// @author Element Finance
/// @title Compound Asset Proxy
contract CompoundAssetProxy is WrappedPosition {
    ICompoundVault public immutable vault;
    uint8 public immutable vaultDecimals;

    constructor(
        address vault_,
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) {
        // the Yearn asset proxy does interesting things here with WrappedPosition

        // I'm not confident this is how the vault is going to work
        vault = ICompoundVault(vault_);

        // not sure what this approve step does, why we're using max
        _token.approve(vault_, type(uint256).max);

        // I'm not entirely sure if this should be IERC20 from our interfaces or some
        // implementation of Compound's CErc20
        vaultDecimals = IERC20(vault_).decimals();
        require(
            uint8(_token.decimals()) == vaultDecimals,
            "Inconsistent decimals"
        );
    }

    function _deposit() internal override returns (uint256, uint256) {
        // load balance of contract
        uint256 amount = token.balanceOf(address(this));

        // deposit into compound
        uint256 userShare = vault.deposit(amount, address(this));

        // Return the amount of shares the user has produced, and the amount of underlying used for it.
        return (userShare, amount);
    }

    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256 _underlyingPerShare
    ) internal override returns (uint256) {
        // do the withdraw
        uint256 amountReceived = vault.withdraw(_shares, address(this), 10000);

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
        return (_amount * _balanceOfUnderlying()) / (10**vaultDecimals);
    }

    //https://github.com/compound-finance/compound-protocol/blob/master/contracts/CToken.sol#L184-L195
    // /**
    //  * @notice Get the underlying balance of the `owner`
    //  * @dev This also accrues interest in a transaction
    //  * @param owner The address of the account to query
    //  * @return The amount of underlying owned by `owner`
    //  */
    // function balanceOfUnderlying(address owner) external returns (uint) {
    //     Exp memory exchangeRate = Exp({mantissa: exchangeRateCurrent()});
    //     (MathError mErr, uint balance) = mulScalarTruncate(exchangeRate, accountTokens[owner]);
    //     require(mErr == MathError.NO_ERROR, "balance could not be calculated");
    //     return balance;
    // }

    /// @notice Get the price per share in the vault
    /// @return The price per share in units of underlying;
    function _balanceOfUnderlying() internal view returns (uint256) {
        return vault.balanceOfUnderlying();
    }
}
