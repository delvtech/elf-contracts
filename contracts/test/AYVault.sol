// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/IYearnVaultV2.sol";

import "../libraries/ERC20.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AToken.sol";

contract AYVault is ERC20, IYearnVault {
    using SafeERC20 for IERC20;
    using Address for address;

    address public token;
    uint256 internal _supply;

    constructor(address _token) ERC20("a ytoken", "yToken") {
        token = _token;
    }

    function deposit(uint256 _amount, address destination)
        external
        override
        returns (uint256)
    {
        uint256 _shares = (_amount * 1e18) / pricePerShare(); // calculate shares
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount); // pull deposit from sender
        _mint(destination, _shares); // mint shares for sender
        _supply += _shares;
        return _shares;
    }

    function withdraw(
        uint256 _shares,
        address destination,
        uint256
    ) external override returns (uint256) {
        uint256 _amount = (_shares * pricePerShare()) / 1e18;
        _burn(msg.sender, _shares);
        _supply -= _shares;
        IERC20(token).safeTransfer(destination, _amount);
        return _amount;
    }

    function pricePerShare() public override view returns (uint256) {
        uint256 balance = ERC20(token).balanceOf(address(this));
        if (balance == 0) return 1e18;
        return (balance * 1e18) / totalSupply();
    }

    function updateShares() external {
        uint256 balance = ERC20(token).balanceOf(address(this));
        AToken(token).mint(address(this), balance / 10);
    }

    function totalSupply() public override view returns (uint256) {
        return _supply;
    }

    function totalAssets() public override view returns (uint256) {
        return ERC20(token).balanceOf(address(this));

    function governance() external override view returns (address) {
        revert("Unimplemented");
    }

    function setDepositLimit(uint256) external override {
        revert("Unimplemented");
    }
}
