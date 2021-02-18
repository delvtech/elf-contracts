pragma solidity ^0.8.0;

import "../libraries/ERC20.sol";
import "../libraries/ERC20Permit.sol";
import "../libraries/DateString.sol";

import "../interfaces/IYC.sol";

contract YC is ERC20Permit, IYC {
    address public tranche;

    constructor(
        address _authority,
        string memory strategySymbol,
        uint256 timestamp
    ) ERC20("Yield Coupon ", "YC:") ERC20Permit("Yield Coupon") {
        tranche = _authority;
        // Write the elfSymbol and expiration time to name and symbol
        DateString.encodeAndWriteTimestamp(strategySymbol, timestamp, _name);
        DateString.encodeAndWriteTimestamp(strategySymbol, timestamp, _symbol);
    }

    modifier onlyMintAuthority() {
        require(msg.sender == tranche, "caller is not an authorized minter");
        _;
    }

    function mint(address _account, uint256 _amount)
        external override
        onlyMintAuthority
    {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount)
        external override
        onlyMintAuthority
    {
        _burn(_account, _amount);
    }
}
