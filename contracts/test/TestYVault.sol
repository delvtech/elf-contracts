// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/IYearnVault.sol";

import "../libraries/ERC20PermitWithSupply.sol";

import "../libraries/ERC20Permit.sol";
import "./TestERC20.sol";

contract TestYVault is ERC20PermitWithSupply {
    address public token;

    constructor(address _token, uint8 _decimals)
        ERC20Permit("test ytoken", "yToken")
    {
        token = _token;
        _setupDecimals(_decimals);
    }

    function deposit(uint256 _amount, address destination)
        external
        returns (uint256)
    {
        uint256 _shares;
        if (totalSupply == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount * (10**decimals)) / pricePerShare(); // calculate shares
        }
        IERC20(token).transferFrom(msg.sender, address(this), _amount); // pull deposit from sender
        _mint(destination, _shares); // mint shares for sender
        return _shares;
    }

    function apiVersion() external pure virtual returns (string memory) {
        return ("0.3.2");
    }

    function withdraw(
        uint256 _shares,
        address destination,
        uint256
    ) external returns (uint256) {
        // Yearn supports this
        if (_shares == type(uint256).max) {
            _shares = balanceOf[msg.sender];
        }
        uint256 _amount = (_shares * pricePerShare()) / (10**decimals);
        _burn(msg.sender, _shares);
        IERC20(token).transfer(destination, _amount);
        return _amount;
    }

    function pricePerShare() public view returns (uint256) {
        uint256 balance = ERC20Permit(token).balanceOf(address(this));
        if (balance == 0) return (10**decimals);
        return (balance * (10**decimals)) / totalSupply;
    }

    function updateShares() external {
        uint256 balance = ERC20Permit(token).balanceOf(address(this));
        TestERC20(token).mint(address(this), balance / 10);
    }

    function totalAssets() public view returns (uint256) {
        return ERC20Permit(token).balanceOf(address(this));
    }

    function governance() external pure returns (address) {
        revert("Unimplemented");
    }

    function setDepositLimit(uint256) external pure {
        revert("Unimplemented");
    }
}
