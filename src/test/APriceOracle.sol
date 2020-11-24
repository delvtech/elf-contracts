// SPDX-License-Identifier: UNLICENSED
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

    uint256 price = 400.5 ether;

    constructor() public {}

    function getPrice(address _fromToken, address _toToken)
        public
        view
        returns (uint256)
    {
        return price;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }
}
