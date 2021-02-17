pragma solidity ^0.8.0;

import "../libraries/ERC20.sol";

contract ElfStub is ERC20 {
    uint256 public underlyingUnitValue = 100;

    // solhint-disable-next-line no-empty-blocks
    constructor() ERC20("ELement Finance", "TestELF") {}

    function setSharesToUnderlying(uint256 _value) external {
        underlyingUnitValue = _value;
    }

    function getSharesToUnderlying(uint256 _shares)
        external
        view
        returns (uint256)
    {
        return _shares * underlyingUnitValue;
    }

    function balanceOfUnderlying(address who) external view returns (uint256) {
        return balanceOf(who) * underlyingUnitValue;
    }

    function mint(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }
}
