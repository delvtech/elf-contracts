// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.16;

import "../WrappedPosition.sol";
import "./TestCToken.sol";

contract TestCAssetProxy is WrappedPosition {
    TestCToken public immutable ctoken;

    constructor(
        address _ctoken,
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) WrappedPosition(_token, _name, _symbol) {
        ctoken = TestCToken(_ctoken);
    }

    // same as CAssetProxy function but uses TestCToken mint function
    function _deposit() internal override returns (uint256, uint256) {
        // Load balance of contract
        uint256 amount = token.balanceOf(address(this));

        // Since ctoken's mint function returns sucess codes
        // we get the balance before and after minting to calculate shares
        uint256 beforeBalance = ctoken.balanceOfUnderlying(address(this));

        // Deposit into compound
        uint256 mintStatus = ctoken.mint(amount);
        require(mintStatus == 0, "compound mint failed");

        // StoGetre ctoken balance after minting
        uint256 afterBalance = ctoken.balanceOfUnderlying(address(this));
        // Calculate ctoken shares minted
        uint256 shares = afterBalance - beforeBalance;
        // Return the amount of shares the user has produced and the amount of underlying used for it.
        return (shares, amount);
    }

    // same as CAssetProxy function but uses TestCToken redeem
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

    // we don't actually care about this function?
    function _underlying(uint256 _amount)
        internal
        override
        pure
        returns (uint256)
    {
        return _amount;
    }
}
