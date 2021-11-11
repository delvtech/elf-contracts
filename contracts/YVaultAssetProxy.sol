// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IYearnVault.sol";
import "./WrappedPosition.sol";
import "./libraries/Authorizable.sol";

/// SECURITY - This contract has an owner address which can migrate funds to a new yearn vault [or other contract
///            with compatible interface] as well as pause deposits and withdraws. This means that any deposited funds
///            have the same security as that address.

/// @author Element Finance
/// @title Yearn Vault v1 Asset Proxy
contract YVaultAssetProxy is WrappedPosition, Authorizable {
    // The addresses of the current yearn vault
    IYearnVault public vault;
    // 18 decimal fractional form of the multiplier which is applied after
    // a vault upgrade. 0 when no upgrade has happened
    uint88 public conversionRate;
    // Bool packed into the same storage slot as vault and conversion rate
    bool public paused;
    uint8 public immutable vaultDecimals;

    /// @notice Constructs this contract and stores needed data
    /// @param vault_ The yearn v2 vault
    /// @param _token The underlying token.
    ///               This token should revert in the event of a transfer failure.
    /// @param _name The name of the token created
    /// @param _symbol The symbol of the token created
    /// @param _governance The address which can upgrade the yearn vault
    /// @param _pauser address which can pause this contract
    constructor(
        address vault_,
        IERC20 _token,
        string memory _name,
        string memory _symbol,
        address _governance,
        address _pauser
    ) WrappedPosition(_token, _name, _symbol) Authorizable() {
        // Authorize the pauser
        _authorize(_pauser);
        // set the owner
        setOwner(_governance);
        // Set the vault
        vault = IYearnVault(vault_);
        // Approve the vault so it can pull tokens from this address
        _token.approve(vault_, type(uint256).max);
        // Load the decimals and set them as an immutable
        uint8 localVaultDecimals = IERC20(vault_).decimals();
        vaultDecimals = localVaultDecimals;
        require(
            uint8(_token.decimals()) == localVaultDecimals,
            "Inconsistent decimals"
        );
    }

    /// @notice Checks that the contract has not been paused
    modifier notPaused() {
        require(!paused, "Paused");
        _;
    }

    /// @notice Makes the actual deposit into the yearn vault
    /// @return Tuple (the shares minted, amount underlying used)
    function _deposit() internal override notPaused returns (uint256, uint256) {
        // Get the amount deposited
        uint256 amount = token.balanceOf(address(this));

        // Deposit and get the shares that were minted to this
        uint256 shares = vault.deposit(amount, address(this));

        // If we have migrated our shares are no longer 1 - 1 with the vault shares
        if (conversionRate != 0) {
            // conversionRate is the fraction of yearnSharePrice1/yearnSharePrices2 at time of migration
            // and so this multiplication will convert between yearn shares in the new vault and
            // those in the old vault
            shares = (shares * conversionRate) / 1e18;
        }

        // Return the amount of shares the user has produced, and the amount used for it.
        return (shares, amount);
    }

    /// @notice Withdraw the number of shares
    /// @param _shares The number of wrapped position shares to withdraw
    /// @param _destination The address to send the output funds
    // @param _underlyingPerShare The possibly precomputed underlying per share
    /// @return returns the amount of funds freed by doing a yearn withdraw
    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256
    ) internal override notPaused returns (uint256) {
        // If the conversion rate is non-zero we have upgraded and so our wrapped shares are
        // not one to one with the original shares.
        if (conversionRate != 0) {
            // Then since conversion rate is yearnSharePrice1/yearnSharePrices2 we divide the
            // wrapped position shares by it because they are equivalent to the first yearn vault shares
            _shares = (_shares * 1e18) / conversionRate;
        }
        // Withdraws shares from the vault. Max loss is set at 100% as
        // the minimum output value is enforced by the calling
        // function in the WrappedPosition contract.
        uint256 amountReceived = vault.withdraw(_shares, _destination, 10000);

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
        // We may have to convert before using the vault price per share
        if (conversionRate != 0) {
            // Imitate the _withdraw logic and convert this amount to yearn vault2 shares
            _amount = (_amount * 1e18) / conversionRate;
        }
        return (_amount * _pricePerShare()) / (10**vaultDecimals);
    }

    /// @notice Get the price per share in the vault
    /// @return The price per share in units of underlying;
    function _pricePerShare() internal view returns (uint256) {
        return vault.pricePerShare();
    }

    /// @notice Function to reset approvals for the proxy
    function approve() external {
        token.approve(address(vault), 0);
        token.approve(address(vault), type(uint256).max);
    }

    /// @notice Allows an authorized address or the owner to pause this contract
    /// @param pauseStatus true for paused, false for not paused
    /// @dev the caller must be authorized
    function pause(bool pauseStatus) external onlyAuthorized {
        paused = pauseStatus;
    }

    /// @notice Function to transition between two yearn vaults
    /// @param newVault The address of the new vault
    /// @param minOutputShares The min of the new yearn vault's shares the wp will receive
    /// @dev WARNING - This function has the capacity to steal all user funds from this
    ///                contract and so it should be ensured that the owner is a high quorum
    ///                governance vote through the time lock.
    function transition(IYearnVault newVault, uint256 minOutputShares)
        external
        onlyOwner
    {
        // Load the current vault's price per share
        uint256 currentPricePerShare = _pricePerShare();
        // Load the new vault's price per share
        uint256 newPricePerShare = newVault.pricePerShare();
        // Load the current conversion rate or set it to 1
        uint256 newConversionRate = conversionRate == 0 ? 1e18 : conversionRate;
        // Calculate the new conversion rate, note by multiplying by the old
        // conversion rate here we implicitly support more than 1 upgrade
        newConversionRate =
            (newConversionRate * newPricePerShare) /
            currentPricePerShare;
        // We now withdraw from the old yearn vault using max shares
        // Note - Vaults should be checked in the future that they still have this behavior
        vault.withdraw(type(uint256).max, address(this), 10000);
        // Approve the new vault
        token.approve(address(newVault), type(uint256).max);
        // Then we deposit into the new vault
        uint256 currentBalance = token.balanceOf(address(this));
        uint256 outputShares = newVault.deposit(currentBalance, address(this));
        // We enforce a min output
        require(outputShares >= minOutputShares, "Not enough output");
        // Change the stored variables
        vault = newVault;
        // because of the truncation yearn vaults can't have a larger diff than ~ billion
        // times larger
        conversionRate = uint88(newConversionRate);
    }
}
