pragma solidity ^0.8.0;

import "../Elf.sol";
import "./TestERC20.sol";

contract ElfStub is Elf {
    uint256 public underlyingUnitValue = 100;

    // solhint-disable-next-line no-empty-blocks
    constructor(address _token) Elf(_token, "ELement Finance", "TestELF") {}

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
    function _withdraw(uint256 amount, address destination)
        internal
        override
        returns (uint256)
    {
        // Send the requested amount converted to underlying
        TestERC20(address(token)).uncheckedTransfer(
            destination,
            amount * underlyingUnitValue
        );
        // Returns the amount of output transferred
        return (amount * underlyingUnitValue);
    }

    function _vault() internal override view returns (IERC20) {
        return IERC20(address(0));
    }

    function setSharesToUnderlying(uint256 _value) external {
        underlyingUnitValue = _value;
    }

    function _underlying(uint256 _shares)
        internal
        override
        view
        returns (uint256)
    {
        return _shares * underlyingUnitValue;
    }
}
