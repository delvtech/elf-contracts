// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0;

import "./interfaces/IERC20.sol";
import "./WrappedPosition.sol";
import "./interfaces/external/CTokenInterfaces.sol";
import "./interfaces/external/ComptrollerInterface.sol";
import "./libraries/Authorizable.sol";

/// @author Element Finance
/// @title Compound Asset Proxy
contract CompoundAssetProxy is WrappedPosition, Authorizable {
    uint8 public immutable underlyingDecimals;
    // The ctoken contract
    CErc20Interface public immutable ctoken;
    // The Compound comptroller contract
    ComptrollerInterface public immutable comptroller;
    // Constant comp token address
    IERC20 public immutable comp;

    /// @notice Constructs this contract and stores needed data
    /// @param _ctoken The underlying ctoken
    /// @param _comptroller The Compound comptroller
    /// @param _comp The address of the COMP governance token
    /// @param _token The underlying token
    /// @param _name The name of the token created
    /// @param _symbol The symbol of the token created
    /// @param _owner The contract owner who is authorized to collect rewards
    constructor(
        address _ctoken,
        address _comptroller,
        IERC20 _comp,
        IERC20 _token,
        string memory _name,
        string memory _symbol,
        address _owner
    ) WrappedPosition(_token, _name, _symbol) {
        _authorize(_owner);
        // Authorize the contract owner
        setOwner(_owner);

        ctoken = CErc20Interface(_ctoken);
        comptroller = ComptrollerInterface(_comptroller);
        comp = _comp;
        // Set approval for the proxy
        _token.approve(_ctoken, type(uint256).max);
        underlyingDecimals = _token.decimals();
        // We must assume the ctoken has 8 decimals to make the correct calculation for exchangeRate
        require(
            IERC20(_ctoken).decimals() == 8,
            "breaks our assumption in exchange rate"
        );
        // Check that the underlying token is the same as ctoken's underlying
        require(address(_token) == CErc20Storage(_ctoken).underlying());
    }

    /// @notice Makes the actual ctoken deposit
    /// @return Tuple (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        // Load balance of contract
        uint256 depositAmount = token.balanceOf(address(this));

        // Since ctoken's mint function returns success codes
        // we get the balance before and after minting to calculate shares
        uint256 beforeBalance = ctoken.balanceOfUnderlying(address(this));

        // Deposit into compound
        uint256 mintStatus = ctoken.mint(depositAmount);
        require(mintStatus == 0, "compound mint failed");

        // StoGetre ctoken balance after minting
        uint256 afterBalance = ctoken.balanceOfUnderlying(address(this));
        // Calculate ctoken shares minted
        uint256 shares = afterBalance - beforeBalance;
        // Return the amount of shares the user has produced and the amount of underlying used for it.
        return (shares, depositAmount);
    }

    /// @notice Withdraw the number of shares
    /// @param _shares The number of shares to withdraw
    /// @param _destination The address to send the output funds
    // @param _underlyingPerShare The possibly precomputed underlying per share
    /// @return Amount of funds freed by doing a withdraw
    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256
    ) internal override returns (uint256) {
        // Since ctoken's redeem function returns sucess codes
        // we get the balance before and after minting to calculate amount
        uint256 beforeBalance = token.balanceOf(address(this));

        // Do the withdraw
        uint256 redeemStatus = ctoken.redeem(_shares);
        require(redeemStatus == 0, "compound redeem failed");

        // Get underlying balance after withdrawing
        uint256 afterBalance = token.balanceOf(address(this));
        // Calculate the amount of funds that were freed
        uint256 amountReceived = afterBalance - beforeBalance;
        // Transfer the underlying to the destination
        // 'token' is an immutable in WrappedPosition
        token.transfer(_destination, amountReceived);

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
        // Load exchange rate
        uint256 exchangeRate = ctoken.exchangeRateStored();

        // Calculate mantissa for the scaled exchange rate
        // 18 point decimal fix + difference in decimals between underlying and ctoken
        uint256 mantissa = 18 + underlyingDecimals - 8;

        // Multiply _amount by exchange rate & correct for decimals
        return ((_amount * exchangeRate) / (10**mantissa));
    }

    /// @notice Collect the comp rewards accrued
    /// @param _destination The address to send the rewards to
    function collectRewards(address _destination) external onlyAuthorized {
        // Set up input params for claimComp
        CErc20Interface[] memory cTokens = new CErc20Interface[](1);
        // Store cToken as an array
        cTokens[0] = ctoken;

        // claim the rewards
        comptroller.claimComp(address(this), cTokens);
        // look up the comp balance to send
        uint256 balance = comp.balanceOf(address(this));
        // send to destination address
        comp.transfer(_destination, balance);
    }
}
