pragma solidity ^0.8.0;

import "../libraries/ERC20.sol";
import "../libraries/ERC20Permit.sol";

contract YC is ERC20Permit {
    address internal _mintAuthority;

    constructor(address _authority)
        ERC20("Yield Coupon", "YC")
        ERC20Permit("Yield Coupon")
    {
        _mintAuthority = _authority;
    }

    modifier onlyMintAuthority() {
        require(
            msg.sender == _mintAuthority,
            "caller is not an authorized minter"
        );
        _;
    }

    function mint(address _account, uint256 _amount)
        external
        onlyMintAuthority
    {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount)
        external
        onlyMintAuthority
    {
        _burn(_account, _amount);
    }
}
