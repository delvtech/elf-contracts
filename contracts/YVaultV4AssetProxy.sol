// SPDX-License-Identifier: Apache-2.0
// WARNING: This has been validated for yearn vaults version 4.2, do not use for lower or higher
//          versions without review
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IYearnVault.sol";
import "./YVaultAssetProxy.sol";

/// @author Element Finance
/// @title Yearn Vault Asset Proxy
contract YVaultV4AssetProxy is YVaultAssetProxy {
    /// @notice Constructs this contract by calling into the super constructor
    /// @param vault_ The yearn v2 vault, must be version 0.4.2
    /// @param _token The underlying token.
    ///               This token should revert in the event of a transfer failure.
    /// @param _name The name of the token created
    /// @param _symbol The symbol of the token created
    constructor(
        address vault_,
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) YVaultAssetProxy(vault_, _token, _name, _symbol) {}

    /// @notice Overrides the version checking to check for 0.4.2 instead
    /// @param _vault The yearn vault address
    /// @dev This function can be overridden by an inheriting upgrade contract
    function _versionCheck(IYearnVault _vault) internal view override {
        string memory apiVersion = _vault.apiVersion();
        require(
            _stringEq(apiVersion, "0.4.2") || _stringEq(apiVersion, "0.4.3"),
            "Unsupported Version"
        );
    }

    /// @notice Converts an input of shares to it's output of underlying or an input
    ///      of underlying to an output of shares, using yearn 's deposit pricing
    /// @param amount the amount of input, shares if 'sharesIn == true' underlying if not
    /// @param sharesIn true to convert from yearn shares to underlying, false to convert from
    ///                 underlying to yearn shares
    /// @dev WARNING - Fails for 0.3.2-0.3.5, please only use with 0.4.2
    /// @return The converted output of either underlying or yearn shares
    function _yearnDepositConverter(uint256 amount, bool sharesIn)
        internal
        view
        override
        returns (uint256)
    {
        // Load the yearn price per share
        uint256 pricePerShare = vault.pricePerShare();
        // If we are converted shares to underlying
        if (sharesIn) {
            // If the input is shares we multiply by the price per share
            return (pricePerShare * amount) / 10**vaultDecimals;
        } else {
            // If the input is in underlying we divide by price per share
            return (amount * 10**vaultDecimals) / (pricePerShare + 1);
        }
    }
}
