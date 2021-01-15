pragma solidity >=0.5.8 <0.8.0;

import "../libraries/ERC20.sol";

contract FYT is ERC20 {
    address internal _mintAuthority;

    constructor(address _authority) public ERC20("Fixed Yield Token", "FYT") {
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
