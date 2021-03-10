// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IElf.sol";

import "./libraries/ERC20.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";

/// @author Element Finance
/// @title Elf Core
abstract contract Elf is ERC20, IElf {
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 public immutable override token;

    /// @notice Constucts this contract
    /// @param _token The underlying token
    /// @param _name the name of this contract
    /// @param _symbol the symbol for this contract
    constructor(
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        token = _token;
        // We set our decimals to be the same as the underlying
        _setupDecimals(_token.decimals());
    }

    /// We expect that the following logic will be present in an integration implementation
    /// which inherits from this contract

    /// @dev Makes the actual deposit into the 'vault'
    /// @return (the shares minted, amount underlying used)
    function _deposit() internal virtual returns (uint256, uint256);

    /// @dev Makes the actual withdraw from the 'vault'
    /// @return returns the amount produced
    function _withdraw(
        uint256,
        address,
        uint256
    ) internal virtual returns (uint256);

    /// @dev Converts between an internal balance representation
    ///      and underlying tokens.
    /// @return returns the amount of underlying the input is worth
    function _underlying(uint256) internal virtual view returns (uint256);

    /// @notice Get the underlying balance of an address
    /// @param _who The address to query
    /// @return The underlying token balance of the address
    function balanceOfUnderlying(address _who)
        external
        override
        view
        returns (uint256)
    {
        return _underlying(balanceOf[_who]);
    }

    /// @notice Returns the amount of the underlying asset a certain amount of shares is worth
    /// @param _shares to calculate underlying value for
    /// @return the value of underlying assets for the given shares
    function getSharesToUnderlying(uint256 _shares)
        external
        override
        view
        returns (uint256)
    {
        return _underlying(_shares);
    }

    /// @notice Entry point to deposit tokens into the Elf contract
    ///         Transfers tokens on behalf of caller so the caller must set
    ///         allowance on the contract prior to call.
    /// @param _amount the amount of underlying tokens to deposit
    /// @param _destination the address to mint too
    /// @return Returns the number of ELF tokens minted
    function deposit(address _destination, uint256 _amount)
        external
        override
        returns (uint256)
    {
        // Send tokens to the proxy
        token.safeTransferFrom(msg.sender, address(this), _amount);
        // Calls our internal deposit function
        (uint256 shares, ) = _deposit();
        // Mint them internal ERC20 tokens coresponding to the deposit
        _mint(_destination, shares);
        return shares;
    }

    /// @notice Entry point to deposit tokens into the Elf contract
    ///         Assumes the tokens were transferred before this was called
    /// @param _destination the destination of this deposit
    /// @return Returns (elf tokens minted, used underlying,
    ///                  senders ELF balance before mint,
    function prefundedDeposit(address _destination)
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // Calls our internal deposit function
        (uint256 shares, uint256 usedUnderlying) = _deposit();

        uint256 balanceBefore = balanceOf[msg.sender];

        // Mint them internal ERC20 tokens coresponding to the deposit
        _mint(_destination, shares);
        return (shares, usedUnderlying, balanceBefore);
    }

    /// @notice Exit point to withdraw tokens from the Elf contract
    /// @param _destination the address which is credited with tokens
    /// @param _shares the amount of shares the user is burning to withdraw underlying
    /// @param _minUnderlying a param which is the min output the caller expects
    /// @return The amount of underlying transferred to the destination
    function withdraw(
        address _destination,
        uint256 _shares,
        uint256 _minUnderlying
    ) public override returns (uint256) {
        return _elfWithdraw(_destination, _shares, _minUnderlying, 0);
    }

    /// @notice This function burns enough tokens from the sender to send _amount
    ///          of underlying to the _destination.
    /// @param _destination the address to send the output to
    /// @param _amount the amount of underlying to try to redeem for
    /// @param _minUnderlying the minium underlying to receive
    /// @return the amount of underlying released
    function withdrawUnderlying(
        address _destination,
        uint256 _amount,
        uint256 _minUnderlying
    ) external override returns (uint256) {
        // First we load the number of underlying per unit of ELF token
        uint256 oneUnit = 10**decimals;
        uint256 underlyingPerElf = _underlying(oneUnit);
        // Then we calculate the number of shares we need
        uint256 shares = (_amount * oneUnit) / underlyingPerElf;
        // Using this we call the normal withdraw function
        return
            _elfWithdraw(
                _destination,
                shares,
                _minUnderlying,
                underlyingPerElf
            );
    }

    /// @notice This internal function allows the caller to provide a precomputed 'underlyingPerElf'
    ///         so that we can avoid calling it again in the internal function
    /// @param _destination the destination to send the output to
    /// @param _shares the number of shares to withdraw
    /// @param _minUnderlying the min amount of output to produce
    /// @param _underlyingPerShare the precomputed shares per underlying
    /// @return the amount of underlying released
    function _elfWithdraw(
        address _destination,
        uint256 _shares,
        uint256 _minUnderlying,
        uint256 _underlyingPerShare
    ) internal returns (uint256) {
        // Burn users ELF shares
        _burn(msg.sender, _shares);

        // Withdraw that many shares from the vault
        uint256 withdrawAmount = _withdraw(
            _shares,
            _destination,
            _underlyingPerShare
        );

        // We revert if this call doesn't produce enough underlying
        // This security feature is useful in some edge cases
        require(withdrawAmount >= _minUnderlying, "Not enough underlying");
        return withdrawAmount;
    }
}
