// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/ICompoundVault.sol";
import "./WrappedPosition.sol";

/// @author Element Finance
/// @title Compound Asset Proxy
contract CompoundAssetProxy is WrappedPosition {
    ICompoundVault public immutable vault;

    // decimals stuff is confusing to me
    uint8 public immutable vaultDecimals;
    mapping(address => uint256) public reserveBalances;

    // it's interesting that this is uint128 whereas the input to the setter function is uint128
    uint128 public reserveUnderlying;
    uint128 public reserveShares;

    // uint256 public reserveSupply; don't understand exactly what this does

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

    function _getReserves() internal view returns (uint256, uint256) {
        return (uint256(reserveUnderlying), uint256(reserveShares));
    }

    function _setReserves(
        uint256 _newReserveUnderlying,
        uint256 _newReserveShares
    ) internal {
        reserveUnderlying = uint128(_newReserveUnderlying);
        reserveShares = uint128(_newReserveShares);
    }

    function _deposit() internal override returns (uint256, uint256) {
        // Load reserves
        (uint256 localUnderlying, uint256 localShares) = _getReserves();
        //Get the amount deposited
        uint256 amount = token.balanceOf(address(this)) - localUnderlying;

        // Calculate the amount of shares the amount deposited is worth
        uint256 neededShares = _compoundDepositConverter(amount, false);

        // Deposit and get the shares that were minted to this
        uint256 shares = vault.deposit(localUnderlying + amount, address(this));

        // calculate the user share
        uint256 userShare = (amount * shares) / (localUnderlying + amount);

        // set the reserves
        _setReserves(0, localShares + shares - userShare);
        // Return the amount of shares the user has produced, and the amount used for it.
        return (userShare, amount);
    }

    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256 _underlyingPerShare
    ) internal override returns (uint256) {
        // load the reserves
        (uint256 localUnderlying, uint256 localShares) = _getReserves();

        // do the withdraw
        uint256 amountReceived = vault.withdraw(
            _shares + localShares,
            address(this),
            10000
        );

        // calculate the user share
        uint256 userShare = (_shares * amountReceived) /
            (localShares + _shares);

        _setReserves(localUnderlying + amountReceived - userShare, 0);
        // Transfer the underlying to the destination 'token' is an immutable in WrappedPosition
        token.transfer(_destination, userShare);
        // Return the amount of underlying
        return userShare;
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
        return (_amount * _pricePerShare()) / (10**vaultDecimals);
    }

    /// @notice Get the price per share in the vault
    /// @return The price per share in units of underlying;
    function _pricePerShare() internal view returns (uint256) {
        return vault.pricePerShare();
    }

    // not sure if we need a compound version of this or not
    function _compoundDepositConverter(uint256 amount, bool sharesIn)
        internal
        virtual
        view
        returns (uint256)
    {
        // Load the yearn total supply and assets
        uint256 compoundTotalSupply = vault.totalSupply();
        uint256 compoundTotalAssets = vault.totalAssets();
        // If we are converted shares to underlying
        if (sharesIn) {
            // then we get the fraction of yearn shares this is and multiply by assets
            return (compoundTotalAssets * amount) / compoundTotalSupply;
        } else {
            // otherwise we figure out the faction of yearn assets this is and see how
            // many assets we get out.
            return (compoundTotalSupply * amount) / compoundTotalAssets;
        }
    }
}
