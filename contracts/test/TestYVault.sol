// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/IYearnVaultV2.sol";

import "../libraries/ERC20WithSupply.sol";

import "./TestERC20.sol";

contract TestYVault is ERC20WithSupply {
    address public token;

    constructor(address _token) ERC20("test ytoken", "yToken") {
        token = _token;
    }

    function deposit(uint256 _amount, address destination)
        external
        returns (uint256)
    {
        uint256 _shares = (_amount * 1e18) / pricePerShare(); // calculate shares
        IERC20(token).transferFrom(msg.sender, address(this), _amount); // pull deposit from sender
        _mint(destination, _shares); // mint shares for sender
        return _shares;
    }

    function withdraw(
        uint256 _shares,
        address destination,
        uint256
    ) external returns (uint256) {
        uint256 _amount = (_shares * pricePerShare()) / 1e18;
        _burn(msg.sender, _shares);
        IERC20(token).transfer(destination, _amount);
        return _amount;
    }

    function pricePerShare() public view returns (uint256) {
        uint256 balance = ERC20(token).balanceOf(address(this));
        if (balance == 0) return 1e18;
        return (balance * 1e18) / totalSupply;
    }

    function updateShares() external {
        uint256 balance = ERC20(token).balanceOf(address(this));
        TestERC20(token).mint(address(this), balance / 10);
    }

    function totalAssets() public view returns (uint256) {
        return ERC20(token).balanceOf(address(this));
    }

    function governance() external pure returns (address) {
        revert("Unimplemented");
    }

    function setDepositLimit(uint256) external pure {
        revert("Unimplemented");
    }
}
