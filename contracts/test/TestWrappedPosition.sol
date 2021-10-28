// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../WrappedPosition.sol";
import "./TestERC20.sol";

contract TestWrappedPosition is WrappedPosition {
    uint256 public underlyingUnitValue = 100;

    constructor(IERC20 _token)
        WrappedPosition(_token, "ELement Finance", "TestWrappedPosition")
    {} // solhint-disable-line no-empty-blocks

    function _deposit() internal override returns (uint256, uint256) {
        // Check how much was deposited
        uint256 deposited = token.balanceOf(address(this));
        // Pretend to send it somewhere else
        TestERC20(address(token)).setBalance(address(this), 0);
        // Return how many shares it's worth and the deposit amount
        return (deposited / underlyingUnitValue, deposited);
    }

    // This withdraw just uses the set balance function in test erc20
    // to set the output location correctly
    function _withdraw(
        uint256 amount,
        address destination,
        uint256
    ) internal override returns (uint256) {
        // Send the requested amount converted to underlying
        TestERC20(address(token)).uncheckedTransfer(
            destination,
            amount * underlyingUnitValue
        );
        // Returns the amount of output transferred
        return (amount * underlyingUnitValue);
    }

    function setSharesToUnderlying(uint256 _value) external {
        underlyingUnitValue = _value;
    }

    function _underlying(uint256 _shares)
        internal
        view
        override
        returns (uint256)
    {
        return _shares * underlyingUnitValue;
    }
}
