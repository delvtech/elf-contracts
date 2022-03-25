// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IWETH.sol";
import "./interfaces/IWrappedPosition.sol";
import "./libraries/ERC20PermitWithSupply.sol";

/// @title Wrapped Convex Position Core
abstract contract WrappedConvexPosition is
    ERC20PermitWithSupply,
    IWrappedPosition
{
    IERC20 public immutable override token;

    /// @notice Constructs this contract
    /// @param _token The underlying token.
    ///               This token should revert in the event of a transfer failure.
    /// @param _name the name of this contract
    /// @param _symbol the symbol for this contract
    constructor(
        address _token,
        string memory _name,
        string memory _symbol
    ) ERC20Permit(_name, _symbol) {
        token = IERC20(_token);
        // We set our decimals to be the same as the underlying
        _setupDecimals(IERC20(_token).decimals());
    }

    /// We expect that the following logic will be present in an integration implementation
    /// which inherits from this contract

    /// @dev Makes the actual deposit into the 'vault'
    /// @return Tuple (shares minted, amount underlying used)
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
    /// @return The amount of underlying the input is worth
    function _sharesToUnderlying(uint256)
        internal
        view
        virtual
        returns (uint256);

    /// @notice Get the underlying balance of an address
    /// @param _who The address to query
    /// @return The underlying token balance of the address
    function balanceOfUnderlying(address _who)
        external
        view
        override
        returns (uint256)
    {
        return _sharesToUnderlying(balanceOf[_who]);
    }

    /// @notice Returns the amount of the underlying asset a certain amount of shares is worth
    /// @param _shares Shares to calculate underlying value for
    /// @return The value of underlying assets for the given shares
    function getSharesToUnderlying(uint256 _shares)
        external
        view
        override
        returns (uint256)
    {
        return _sharesToUnderlying(_shares);
    }

    /// @notice Entry point to deposit tokens into the Wrapped Position contract
    ///         Transfers tokens on behalf of caller so the caller must set
    ///         allowance on the contract prior to call.
    /// @param _amount The amount of underlying tokens to deposit
    /// @param _destination The address to mint to
    /// @return Returns the number of Wrapped Position tokens minted
    function deposit(address _destination, uint256 _amount)
        external
        override
        returns (uint256)
    {
        // Send tokens to the proxy
        token.transferFrom(msg.sender, address(this), _amount);
        // Calls our internal deposit function
        (uint256 shares, ) = _deposit();
        // Mint them internal ERC20 tokens corresponding to the deposit
        _mint(_destination, shares);
        return shares;
    }

    /// @notice Entry point to deposit tokens into the Wrapped Position contract
    ///         Assumes the tokens were transferred before this was called
    /// @param _destination the destination of this deposit
    /// @return Returns (WP tokens minted, used underlying,
    ///                  senders WP balance before mint)
    /// @dev WARNING - The call which funds this method MUST be in the same transaction
    //                 as the call to this method or you risk loss of funds
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

        uint256 balanceBefore = balanceOf[_destination];

        // Mint them internal ERC20 tokens corresponding to the deposit
        _mint(_destination, shares);
        return (shares, usedUnderlying, balanceBefore);
    }

    /// @notice Exit point to withdraw tokens from the Wrapped Position contract
    /// @param _destination The address which is credited with tokens
    /// @param _shares The amount of shares the user is burning to withdraw underlying
    /// @param _minUnderlying The min output the caller expects
    /// @return The amount of underlying transferred to the destination
    function withdraw(
        address _destination,
        uint256 _shares,
        uint256 _minUnderlying
    ) public override returns (uint256) {
        return _positionWithdraw(_destination, _shares, _minUnderlying, 0);
    }

    /// @notice This function burns enough tokens from the sender to send _amount
    ///          of underlying to the _destination.
    /// @param _destination The address to send the output to
    /// @param _amount The amount of underlying to try to redeem for
    /// @param _minUnderlying The minium underlying to receive
    /// @return The amount of underlying released, and shares used
    function withdrawUnderlying(
        address _destination,
        uint256 _amount,
        uint256 _minUnderlying
    ) external override returns (uint256, uint256) {
        // First we load the number of underlying per unit of Wrapped Position token
        uint256 oneUnit = 10**decimals;
        uint256 underlyingPerShare = _sharesToUnderlying(oneUnit);
        // Then we calculate the number of shares we need
        uint256 shares = (_amount * oneUnit) / underlyingPerShare;
        // Using this we call the normal withdraw function
        uint256 underlyingReceived = _positionWithdraw(
            _destination,
            shares,
            _minUnderlying,
            underlyingPerShare
        );
        return (underlyingReceived, shares);
    }

    /// @notice This internal function allows the caller to provide a precomputed 'underlyingPerShare'
    ///         so that we can avoid calling it again in the internal function
    /// @param _destination The destination to send the output to
    /// @param _shares The number of shares to withdraw
    /// @param _minUnderlying The min amount of output to produce
    /// @param _underlyingPerShare The precomputed shares per underlying
    /// @return The amount of underlying released
    function _positionWithdraw(
        address _destination,
        uint256 _shares,
        uint256 _minUnderlying,
        uint256 _underlyingPerShare
    ) internal returns (uint256) {
        // Withdraw that many shares from the vault
        uint256 withdrawAmount = _withdraw(
            _shares,
            _destination,
            _underlyingPerShare
        );

        // Burn users shares
        // Note: we must burn shares after calling _withdraw to accurately determine the amount of underlying out
        _burn(msg.sender, _shares);

        // We revert if this call doesn't produce enough underlying
        // This security feature is useful in some edge cases
        require(withdrawAmount >= _minUnderlying, "Not enough underlying");
        return withdrawAmount;
    }
}
