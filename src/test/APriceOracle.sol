pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract APriceOracle {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 val1 = 400.5 ether;
    uint256 val2 = 1 ether;

    constructor() public {}

    function getPrice(address _fromToken, address _toToken)
        public
        view
        returns (uint256)
    {
        return val1;
    }

    function setPrice(uint256 _val) public {
        val1 = _val;
    }

    function getPrice2() public view returns (uint256) {
        return val2;
    }

    function setPrice2(uint256 _val) public returns (uint256) {
        val2 = _val;
    }
}
