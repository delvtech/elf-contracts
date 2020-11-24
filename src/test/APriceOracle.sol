// SPDX-License-Identifier: Apache-2.0
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

    uint256 public price = 400.5 ether;

    constructor() public {} // solhint-disable-line no-empty-blocks

    function getPrice(address _fromToken, address _toToken)
        public
        view
        returns (uint256)
    {
        require(_fromToken != address(0));
        require(_toToken != address(0));
        return price;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }
}
