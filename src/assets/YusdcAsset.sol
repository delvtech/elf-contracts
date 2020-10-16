pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./BaseElementYVaultAsset.sol";

contract YusdcAsset is BaseElementYVaultAsset {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant USDC = address(
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    );
    address public constant VAULT = address(
        0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e
    );

    constructor(address _strategy)
        public
        BaseElementYVaultAsset(msg.sender, _strategy, VAULT, USDC)
    {} // solhint-disable no-empty-blocks
}
