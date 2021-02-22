// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IElf.sol";

import "./libraries/ERC20Permit.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";

/// @author Element Finance
/// @title Elf Core
abstract contract Elf is ERC20Permit, IElf {
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 public override token;

    constructor(
        address _token,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        token = IERC20(_token);
    }

    /// We expect that this logic will be present in an integration implementation
    /// which inherits from this contracts
    /// @dev Makes the actual deposit into the 'vault'
    /// @return (the shares minted, amount underlying used)
    function _deposit() internal virtual returns (uint256, uint256);
    /// @dev Makes the actual withdraw from the 'vault'
    /// @return returns the amount produced
    function _withdraw(uint256) internal virtual returns (uint256);
    /// @dev Converts between an internal balance representation
    ///      and underlying tokens.    
    function _underlying(uint256) internal view virtual returns (uint256);
    /// @dev Returns the IERC20 coded vault address for the balance
    ///      looks, may be depreciated in future.
    function _vault() internal view virtual returns(IERC20);

    /// @notice Get the underlying balance of an address
    /// @param _who The address to query
    /// @return The underlying token balance of the address
    function balanceOfUnderlying(address _who) external view override returns (uint256) {
        return _underlying(balanceOf(_who));
    }

    /// @notice Returns the amount of the underlying asset a certain amount of shares is worth
    /// @param _shares to calculate underlying value for
    /// @return the value of underlying assets for the given shares
    function getSharesToUnderlying(uint256 _shares)
        external
        view
        override
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
        external override
        returns (uint256)
    {
        // Send tokens to the proxy
        token.safeTransferFrom(msg.sender, address(this), _amount);
        // Calls our internal deposit function
        (uint256 shares, uint256 _unused) = _deposit(); 
        // Mint them internal ERC20 tokens coresponding to the deposit
        _mint(_destination, shares);
        return shares;
    }

    // TODO - Overload the balance storage map to store the total underlying
    //        minted and return that fact as well. This will save and sstore
    //        and sload in the the Tranche contract.

    /// @notice Entry point to deposit tokens into the Elf contract
    ///         Assumes the tokens were transferred before this was called
    /// @param _destination the destination of this deposit
    /// @return Returns (elf tokens minted, used underlying, 
    ///                  senders ELF balance before mint,
    function prefundedDeposit(address _destination)
        external override
        returns (uint256, uint256, uint256)
    {
        // Calls our internal deposit function
        (uint256 shares, uint256 usedUnderlying) = _deposit();
        // TODO - When we roll our own custom token encoding this sstore can be collapsed
        // into the one that's done in mint.
        uint256 balanceBefore = balanceOf(msg.sender);
        // Mint them internal ERC20 tokens coresponding to the deposit
        _mint(_destination, shares);
        return (shares, usedUnderlying, balanceBefore);
    }

    /// @notice Exit point to withdraw tokens from the Elf contract
    /// @param _destination the address which is credited with tokens
    /// @param _shares the amount of shares the user is burning to withdraw underlying
    /// @param _minUnderlying a param which is the min output the caller expects
    /// @return The amount of underlying transferred to the destination
    function withdraw(address _destination, uint256 _shares, uint256 _minUnderlying)
        public override
        returns (uint256)
    {
        // Burn users ELF shares
        _burn(msg.sender, _shares);

        // Withdraw that many shares from the vault
        uint256 withdrawAmount = _withdraw(_shares);
        // Burn the shares from the caller

        // We revert if this call doesn't produce enough underlying
        // This security feature is useful in some edge cases
        require(withdrawAmount > _minUnderlying, "Not enough underlying");
        // Moves the token to the caller
        token.safeTransfer(_destination, withdrawAmount);
        return withdrawAmount;
    }

    /// @notice This function burns enough tokens from the sender to send _amount
    ///          of underlying to the _destination.
    /// @param _destination the address to send the output to
    /// @param _amount the min amount of underlying to redeem out.
    function withdrawUnderlying(address _destination, uint256 _amount) external override returns (uint256) {
        // First we load the number of underlying per unit of ELF token
        uint256 underlyingPerElf = _underlying(1e18);
        // Then we calculate the number of shares we need
        uint256 shares = (_amount*1e18)/underlyingPerElf;
        // Using this we call the normal withdraw function
        withdraw(_destination, shares, _amount);
    }
}
