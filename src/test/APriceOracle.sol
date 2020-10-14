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

    constructor() public {}

    function getPrice(address fromToken, address toToken)
        public
        view
        returns (uint256)
    {
        return 2;
    }
}
