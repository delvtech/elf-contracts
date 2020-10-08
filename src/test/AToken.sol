pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract AToken is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    constructor(address sender) public ERC20("a token", "TOKEN") {
        mint(sender, 100000);
    }

    function mint(address account, uint256 amount) internal {
        _mint(account, amount);
    }
}
