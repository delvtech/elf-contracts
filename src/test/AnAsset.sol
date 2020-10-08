pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract AnAsset {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;


    address public governance;
    address public strategy;

    constructor(address _strategy) public {
        governance = msg.sender;
        strategy = _strategy;
    }

    function deposit(uint256 _amount, address _sender) external {
        
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == strategy, "!strategy");
    }

    function balanceOf() public view returns (uint256) {
        // TODO
        return 0;
    }

    function _getPrice() internal view returns (uint256 p) {
        // TODO: price oracle
        return 0;
    }
}
