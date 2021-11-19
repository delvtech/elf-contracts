// SPDX-License-Identifier: Apache-2.0
// WARNING: This has been validated for yearn vaults up to version 0.3.5.
// Using this code with any later version can be unsafe.
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IYearnVault.sol";
import "./WrappedPosition.sol";

/// @author Element Finance
/// @title Yearn Vault v1 Asset Proxy
contract YVaultAssetProxy is WrappedPosition {
    IYearnVault public immutable vault;
    uint8 public immutable vaultDecimals;

    // This contract allows deposits to a reserve which can
    // be used to short circuit the deposit process and save gas

    // The following mapping tracks those non-transferable deposits
    mapping(address => uint256) public reserveBalances;
    // These variables store the token balances of this contract and
    // should be packed by solidity into a single slot.
    uint128 public reserveUnderlying;
    uint128 public reserveShares;
    // This is the total amount of reserve deposits
    uint256 public reserveSupply;

    /// @notice Constructs this contract and stores needed data
    /// @param vault_ The yearn v2 vault
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
        // We check that this is a compatible yearn version
        _versionCheck(IYearnVault(vault_));
    }

    /// @notice An override-able version checking function, reverts if the vault has the wrong version
    /// @param _vault The yearn vault address
    /// @dev This function can be overridden by an inheriting upgrade contract
    function _versionCheck(IYearnVault _vault) internal view virtual {
        string memory apiVersion = _vault.apiVersion();
        require(
            _stringEq(apiVersion, "0.3.0") ||
                _stringEq(apiVersion, "0.3.1") ||
                _stringEq(apiVersion, "0.3.2") ||
                _stringEq(apiVersion, "0.3.3") ||
                _stringEq(apiVersion, "0.3.4") ||
                _stringEq(apiVersion, "0.3.5"),
            "Unsupported Version"
        );
    }

    /// @notice checks if two strings are equal
    /// @param s1 string one
    /// @param s2 string two
    /// @return bool whether they are equal
    function _stringEq(string memory s1, string memory s2)
        internal
        pure
        returns (bool)
    {
        bytes32 h1 = keccak256(abi.encodePacked(s1));
        bytes32 h2 = keccak256(abi.encodePacked(s2));
        return (h1 == h2);
    }

    /// @notice This function allows a user to deposit to the reserve
    ///      Note - there's no incentive to do so. You could earn some
    ///      interest but less interest than yearn. All deposits use
    ///      the underlying token.
    /// @param _amount The amount of underlying to deposit
    function reserveDeposit(uint256 _amount) external {
        // Transfer from user, note variable 'token' is the immutable
        // inherited from the abstract WrappedPosition contract.
        token.transferFrom(msg.sender, address(this), _amount);
        // Load the reserves
        (uint256 localUnderlying, uint256 localShares) = _getReserves();
        // Calculate the total reserve value
        uint256 totalValue = localUnderlying;
        totalValue += _yearnDepositConverter(localShares, true);
        // If this is the first deposit we need different logic
        uint256 localReserveSupply = reserveSupply;
        uint256 mintAmount;
        if (localReserveSupply == 0) {
            // If this is the first mint the tokens are exactly the supplied underlying
            mintAmount = _amount;
        } else {
            // Otherwise we mint the proportion that this increases the value held by this contract
            mintAmount = (localReserveSupply * _amount) / totalValue;
        }

        // This hack means that the contract will never have zero balance of underlying
        // which levels the gas expenditure of the transfer to this contract. Permanently locks
        // the smallest possible unit of the underlying.
        if (localUnderlying == 0 && localShares == 0) {
            _amount -= 1;
        }
        // Set the reserves that this contract has more underlying
        _setReserves(localUnderlying + _amount, localShares);
        // Note that the sender has deposited and increase reserveSupply
        reserveBalances[msg.sender] += mintAmount;
        reserveSupply = localReserveSupply + mintAmount;
    }

    /// @notice This function allows a holder of reserve balance to withdraw their share
    /// @param _amount The number of reserve shares to withdraw
    function reserveWithdraw(uint256 _amount) external {
        // Remove 'amount' from the balances of the sender. Because this is 8.0 it will revert on underflow
        reserveBalances[msg.sender] -= _amount;
        // We load the reserves
        (uint256 localUnderlying, uint256 localShares) = _getReserves();
        uint256 localReserveSupply = reserveSupply;
        // Then we calculate the proportion of the shares to redeem
        uint256 userShares = (localShares * _amount) / localReserveSupply;
        // First we withdraw the proportion of shares tokens belonging to the caller
        uint256 freedUnderlying = vault.withdraw(userShares, address(this), 0);
        // We calculate the amount of underlying to send
        uint256 userUnderlying = (localUnderlying * _amount) /
            localReserveSupply;

        // We then store the updated reserve amounts
        _setReserves(
            localUnderlying - userUnderlying,
            localShares - userShares
        );
        // We note a reduction in local supply
        reserveSupply = localReserveSupply - _amount;

        // We send the redemption underlying to the caller
        // Note 'token' is an immutable from shares
        token.transfer(msg.sender, freedUnderlying + userUnderlying);
    }

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
        return (userShare, amount);
    }

    /// @notice Withdraw the number of shares and will short circuit if it can
    /// @param _shares The number of shares to withdraw
    /// @param _destination The address to send the output funds
    /// @param _underlyingPerShare The possibly precomputed underlying per share
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
        (uint256 localUnderlying, uint256 localShares) = _getReserves();
        // Calculate the amount of shares the amount deposited is worth
        uint256 needed = (_shares * _pricePerShare()) / (10**vaultDecimals);
        // If we have enough underlying we don't have to actually withdraw
        if (needed < localUnderlying) {
            // We set the reserves to be the new reserves
            _setReserves(localUnderlying - needed, localShares + _shares);
            // Then transfer needed underlying to the destination
            // 'token' is an immutable in WrappedPosition
            token.transfer(_destination, needed);
            // Short circuit and return
            return (needed);
        }
        // If we don't have enough local reserves we do the actual withdraw
        // Withdraws shares from the vault. Max loss is set at 100% as
        // the minimum output value is enforced by the calling
        // function in the WrappedPosition contract.
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
        view
        override
        returns (uint256)
    {
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

    /// @notice Converts an input of shares to it's output of underlying or an input
    ///      of underlying to an output of shares, using yearn 's deposit pricing
    /// @param amount the amount of input, shares if 'sharesIn == true' underlying if not
    /// @param sharesIn true to convert from yearn shares to underlying, false to convert from
    ///                 underlying to yearn shares
    /// @dev WARNING - In yearn 0.3.1 - 0.3.5 this is an exact match for deposit logic
    ///                but not withdraw logic in versions 0.3.2-0.3.5. In versions 0.4.0+
    ///                it is not a match for yearn deposit ratios.
    /// @return The converted output of either underlying or yearn shares
    function _yearnDepositConverter(uint256 amount, bool sharesIn)
        internal
        view
        virtual
        returns (uint256)
    {
        // Load the yearn total supply and assets
        uint256 yearnTotalSupply = vault.totalSupply();
        uint256 yearnTotalAssets = vault.totalAssets();
        // If we are converted shares to underlying
        if (sharesIn) {
            // then we get the fraction of yearn shares this is and multiply by assets
            return (yearnTotalAssets * amount) / yearnTotalSupply;
        } else {
            // otherwise we figure out the faction of yearn assets this is and see how
            // many assets we get out.
            return (yearnTotalSupply * amount) / yearnTotalAssets;
        }
    }
}
