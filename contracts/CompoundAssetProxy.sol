// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/ICompoundVault.sol";
import "./WrappedPosition.sol";
import "./interfaces/CTokenInterfaces.sol";

/// @author Element Finance
/// @title Compound Asset Proxy
contract CompoundAssetProxy is WrappedPosition {
    ICompoundVault public immutable vault;
    uint8 public immutable vaultDecimals;
    CTokenInterface public immutable ctoken;

    constructor(
        address vault_,
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) {
        // the Yearn asset proxy does interesting things here with WrappedPosition

        // I'm not confident this is how the vault is going to work
        vault = ICompoundVault(vault_);

        _token.approve(vault_, type(uint256).max);

        // I'm not entirely sure if this should be IERC20 from our interfaces or some
        // implementation of Compound's CErc20
        vaultDecimals = IERC20(vault_).decimals();
        require(
            uint8(_token.decimals()) == vaultDecimals,
            "Inconsistent decimals"
        );
    }

    /// @notice Makes the actual deposit into the vault
    /// @return Tuple (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        // load balance of contract
        uint256 amount = token.balanceOf(address(this));

        // deposit into compound
        uint256 share = vault.deposit(amount, address(this));

        // Return the amount of shares the user has produced, and the amount of underlying used for it.
        return (share, amount);
    }

    /// @notice Withdraw the number of shares
    /// @param _shares The number of shares to withdraw
    /// @param _destination The address to send the output funds
    /// @param _underlyingPerShare The possibly precomputed underlying per share
    /// @return returns the amount of funds freed by doing a withdraw
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
        // TODO: dont' think that input param is right
        return
            (_amount * _balanceOfUnderlying(address(this))) /
            (10**vaultDecimals);
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

    //https://github.com/compound-finance/compound-protocol/blob/fcf067f6fa50a93ff9125f5f0abae0ae98d1e8b0/contracts/Comptroller.sol#L1287
    // /**
    //  * @notice Claim all comp accrued by the holders
    //  * @param holders The addresses to claim COMP for
    //  * @param cTokens The list of markets to claim COMP in
    //  * @param borrowers Whether or not to claim COMP earned by borrowing
    //  * @param suppliers Whether or not to claim COMP earned by supplying
    //  */
    // function claimComp(address[] memory holders, CToken[] memory cTokens, bool borrowers, bool suppliers) public {
    //     for (uint i = 0; i < cTokens.length; i++) {
    //         CToken cToken = cTokens[i];
    //         require(markets[address(cToken)].isListed, "market must be listed");
    //         if (borrowers == true) {
    //             Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});
    //             updateCompBorrowIndex(address(cToken), borrowIndex);
    //             for (uint j = 0; j < holders.length; j++) {
    //                 distributeBorrowerComp(address(cToken), holders[j], borrowIndex);
    //             }
    //         }
    //         if (suppliers == true) {
    //             updateCompSupplyIndex(address(cToken));
    //             for (uint j = 0; j < holders.length; j++) {
    //                 distributeSupplierComp(address(cToken), holders[j]);
    //             }
    //         }
    //     }
    //     for (uint j = 0; j < holders.length; j++) {
    //         compAccrued[holders[j]] = grantCompInternal(holders[j], compAccrued[holders[j]]);
    //     }
    // }

    /// @notice Get the price per share in the vault
    /// @return The price per share in units of underlying;
    function _balanceOfUnderlying(address owner)
        internal
        view
        returns (uint256)
    {
        // TODO: add exchange rate details
        uint256 exchangeRate = ctoken.exchangeRateCurrent();
        // TODO: it looks like the balanceOfUnderlying might already do the exchange rate?

        return vault.balanceOfUnderlying();
    }
}
