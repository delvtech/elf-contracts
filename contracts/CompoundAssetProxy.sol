// SPDX-License-Identifier: Apache-2.0
// WARNING: This has been validated for yearn vaults up to version 0.2.11.
// Using this code with any later version can be unsafe.
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IYearnVault.sol";
import "./WrappedPosition.sol";

/// @author Element Finance
/// @title Compound Asset Proxy
contract CompoundAssetProxy is WrappedPosition {
    IYearnVault public immutable vault;
    uint8 public immutable vaultDecimals;

    // The following mapping tracks those non-transferable deposits
    mapping(address => uint256) public reserveBalances;
    // These variables store the token balances of this contract and
    // should be packed by solidity into a single slot.
    uint128 public reserveUnderlying;
    uint128 public reserveShares;
    // This is the total amount of reserve deposits
    uint256 public reserveSupply;

    /// @notice Constructs this contract and stores needed data
    /// @param vault_ The compound vault
    /// @param _token The underlying token.
    ///               This token should revert in the event of a transfer failure.
    /// @param _name The name of the token created
    /// @param _symbol The symbol of the token created
    constructor(
        address vault_,
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) WrappedPosition(_token, _name, _symbol) {
        vault = IYearnVault(vault_);
        _token.approve(vault_, type(uint256).max);
        uint8 localVaultDecimals = IERC20(vault_).decimals();
        vaultDecimals = localVaultDecimals;
        require(
            uint8(_token.decimals()) == localVaultDecimals,
            "Inconsistent decimals"
        );
    }

    /// @notice This function allows a user to deposit to the reserve
    /// @param _amount The amount of underlying to deposit
    function reserveDeposit(uint256 _amount) external {}

    /// @notice This function allows a holder of reserve balance to withdraw their share
    /// @param _amount The number of reserve shares to withdraw
    function reserveWithdraw(uint256 _amount) external {}

    function priceCheck() external {}

    /// @notice Makes the actual deposit into the yearn vault
    ///         Tries to use the local balances before depositing
    /// @return Tuple (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        //Load reserves
        (uint256 localUnderlying, uint256 localShares) = _getReserves();
        // Get the amount deposited
        uint256 amount = token.balanceOf(address(this)) - localUnderlying;
        // fixing for the fact there's an extra underlying
        if (localUnderlying != 0 || localShares != 0) {
            amount -= 1;
        }
        // Calculate the amount of shares the amount deposited is worth
        uint256 neededShares = _yearnDepositConverter(amount, false);

        // If we have enough in local reserves we don't call out for deposits
        if (localShares > neededShares) {
            // We set the reserves
            _setReserves(localUnderlying + amount, localShares - neededShares);
            // And then we short circuit execution and return
            return (neededShares, amount);
        }
        // Deposit and get the shares that were minted to this
        uint256 shares = vault.deposit(localUnderlying + amount, address(this));

        // calculate the user share
        uint256 userShare = (amount * shares) / (localUnderlying + amount);

        // We set the reserves
        _setReserves(0, localShares + shares - userShare);
        // Return the amount of shares the user has produced, and the amount used for it.
    }

    /// @notice Helper to get the reserves with one sload
    /// @return Tuple (reserve underlying, reserve shares)
    function _getReserves() internal view returns (uint256, uint256) {
        return (uint256(reserveUnderlying), uint256(reserveShares));
    }

    /// @notice Helper to set reserves using one sstore
    /// @param _newReserveUnderlying The new reserve of underlying
    /// @param _newReserveShares The new reserve of wrapped position shares
    function _setReserves(
        uint256 _newReserveUnderlying,
        uint256 _newReserveShares
    ) internal {
        reserveUnderlying = uint128(_newReserveUnderlying);
        reserveShares = uint128(_newReserveShares);
    }

    /// @notice Withdraw the number of shares and will short circuit if it can
    /// @param _shares The number of shares to withdraw
    /// @param _destination The address to send the output funds
    /// @param _underlyingPerShare The possibly precomputed underlying per share
    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256 _underlyingPerShare
    ) internal override returns (uint256) {}
}
