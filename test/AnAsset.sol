pragma solidity >=0.5.8 <0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AnAsset is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    constructor(address sender) public ERC20("an asset", "ASSET") {
        mint(sender, 100000);
    }

    function mint(address account, uint256 amount) internal {
        _mint(account, amount);
    }
}
