// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/IYearnVaultV2.sol";
import "../Elf.sol";

import "../libraries/SafeERC20.sol";

/// @author Element Finance
/// @title Yearn Vault v1 Asset Proxy
contract YVaultAssetProxy is Elf {
    using SafeERC20 for IERC20;

    IYearnVault public immutable vault;
    uint8 public immutable vaultDecimals;

    // This contract allows deposits to a reserve which can
    // be used to short circut the deposit process and save gas

    // The following mapping tracks those non-transferable deposits
    mapping(address => uint256) public reserveBalances;
    // These variables store the token balances of this contract and
    // should be packed by solidity into a single slot.
    uint128 public reserveUnderlying;
    uint128 public reserveElf;
    // This is the total amount of reserve deposits
    uint256 public reserveSupply;

    /// @notice Constructs this contract and stores needed data
    /// @param vault_ the yearn v2 vault
    /// @param _token the underlying token
    /// @param _name the name of the token created
    /// @param _symbol the symbol of the token created
    constructor(
        address vault_,
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) Elf(_token, _name, _symbol) {
        vault = IYearnVault(vault_);
        _token.approve(vault_, type(uint256).max);
        vaultDecimals = IERC20(vault_).decimals();
    }

    /// @notice This function allows a user to deposit to the reserve
    ///      Note - there's no incentive to do so you would earn some
    ///      interest but less interest than yearn. All deposits use
    ///      the underlying token.
    /// @param amount The amount of underlying to deposit
    function reserveDeposit(uint256 amount) external {
        // Transfer from user, note variable 'token' is the immutable
        // inheritied from the abstract Elf contract.
        token.transferFrom(msg.sender, address(this), amount);
        // Load the reserves
        (uint256 localUnderlying, uint256 localElf) = _getReserves();
        // Calculate the total reserve value
        uint256 totalValue = localUnderlying;
        totalValue += _underlying(localElf);
        // If this is the first deposit we need different logic
        uint256 localReserveSupply = reserveSupply;
        uint256 mintAmount;
        if (localReserveSupply == 0) {
            // If this is the first mint the tokens are exactly the supplied underlying
            mintAmount = amount;
        } else {
            // Otherwise we mint the proportion that this increases the value held by this contract
            mintAmount = (localReserveSupply * amount) / totalValue;
        }

        // This hack means that the contract will never have zero balance of underlying
        // which levels the gas expenditure of the transfer to this contract. Permanently locks
        // the smallest possible unit of the underlying.
        if (localUnderlying == 0 && localElf == 0) {
            amount -= 1;
        }
        // Set the reserves that this contract has more underlying
        _setReserves(localUnderlying + amount, localElf);
        // Note that the sender has deposited and increase reserveSupply
        reserveBalances[msg.sender] += mintAmount;
        reserveSupply = localReserveSupply + mintAmount;
    }

    /// @notice This function allows a holder of reserve balance to withdraw their share
    /// @param amount The number of reserve shares to withdraw
    function reserveWithdraw(uint256 amount) external {
        // Remove 'amount' from the balances of the sender. Because this is 8.0 it will revert on underflow
        reserveBalances[msg.sender] -= amount;
        // We load the reserves
        (uint256 localUnderlying, uint256 localElf) = _getReserves();
        uint256 localReserveSupply = reserveSupply;
        // Then we calculate the proportion of the ELF to redeem
        uint256 userElf = (localElf * amount) / localReserveSupply;
        // First we withdraw the proportion of ELF tokens belonging to the caller
        uint256 freedUnderlying = vault.withdraw(userElf, address(this), 0);
        // We calculate the amount of underlying to send
        uint256 userUnderlying = (localUnderlying * amount) /
            localReserveSupply;
        // We send the redemption underlying to the caller
        // Note 'token' is an immutable from Elf
        token.transfer(msg.sender, freedUnderlying + userUnderlying);
        // We then store the updated reserve amounts
        _setReserves(localUnderlying - userUnderlying, localElf - userElf);
        // We note a reduction in local supply
        reserveSupply = localReserveSupply - amount;
    }

    /// @notice Makes the actual deposit into the yearn vault
    ///         Tries to use the local balances before depositing
    /// @return (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        //Load reserves
        (uint256 localUnderlying, uint256 localElf) = _getReserves();
        // Get the amount deposited
        uint256 amount = token.balanceOf(address(this)) - localUnderlying;
        // fixing for the fact there's an extra underlying
        if (localUnderlying != 0 || localElf != 0) {
            amount -= 1;
        }
        // Calculate the amount of Elf the amount deposited is worth
        // Note - to get a realistic reading and avoid rounding errors we
        // use the method of the yearn vault instead of '_pricePerShare'
        uint256 yearnTotalSupply = vault.totalSupply();
        uint256 yearnTotalAssets = vault.totalAssets();
        uint256 neededElf = (amount * yearnTotalSupply) / yearnTotalAssets;
        // If we have enough in local reserves we don't call out for deposits
        if (localElf > neededElf) {
            // We set the reserves
            _setReserves(localUnderlying + amount, localElf - neededElf);
            // And then we short circut execution and return
            return (neededElf, amount);
        }
        // Deposit and get the shares that were minted to this
        uint256 shares = vault.deposit(localUnderlying + amount, address(this));
        // We set the reserves
        _setReserves(0, shares - neededElf);
        // Return the amount of elf the user needs, and the amount used for it.
        return (neededElf, amount);
    }

    /// @notice withdraw the number of shares and will short circut if it can
    /// @param _shares the number of shares to withdraw
    /// @param _destination the address to send the output funds
    /// @param _underlyingPerShare the possibly precomputed underlying per share
    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256 _underlyingPerShare
    ) internal override returns (uint256) {
        // If we do not have it we load the price per share
        if (_underlyingPerShare == 0) {
            _underlyingPerShare = _pricePerShare();
        }
        // We load the reserves
        (uint256 localUnderlying, uint256 localElf) = _getReserves();
        // If we have enough underlying we don't have to actually withdraw
        uint256 needed = (_shares * _underlyingPerShare) / 10**vaultDecimals;
        if (needed < localUnderlying) {
            // We set the reserves to be the new reserves
            _setReserves(localUnderlying - needed, localElf + _shares);
            // Then transfer needed underlying to the destination
            // 'token' is an immutable in Elf
            token.transfer(_destination, needed);
            // Short circut and return
            return (needed);
        }
        // If we don't have enough local reserves we do the actual withdraw
        // Withdraws shares from the vault with max loss 0.01%
        uint256 amountReceived = vault.withdraw(
            _shares + localElf,
            address(this),
            1
        );
        _setReserves(amountReceived - needed, 0);
        // Transfer the underlying to the destination 'token' is an immutable in elf
        token.transfer(_destination, needed);
        // Return the amount of underlying
        return needed;
    }

    /// @notice get the underlying amount of tokens per shares given
    /// @param amount the amount of shares you want to know the value of
    /// @return value of shares in underlying token
    function _underlying(uint256 amount)
        internal
        override
        view
        returns (uint256)
    {
        uint256 yearnTotalSupply = vault.totalSupply();
        uint256 yearnTotalAssets = vault.totalAssets();
        return (yearnTotalAssets * amount) / yearnTotalSupply;
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

    /// @notice Helper to get the reserves with one sload
    /// @return (reserve underlying, reserve elf)
    function _getReserves() internal view returns (uint256, uint256) {
        return (uint256(reserveUnderlying), uint256(reserveElf));
    }

    /// @notice helper to set reserves using one sstore
    /// @param newReserveUnderlying the new reserve of underlying
    /// @param newReserveElf the new reserve of elf
    function _setReserves(uint256 newReserveUnderlying, uint256 newReserveElf)
        internal
    {
        reserveUnderlying = uint128(newReserveUnderlying);
        reserveElf = uint128(newReserveElf);
    }
}
