pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./BaseElementYVaultAsset.sol";

contract YdaiAsset is BaseElementYVaultAsset {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant DAI = address(
        0x6B175474E89094C44Da98b954EedeAC495271d0F
    );
    address public constant VAULT = address(
        0xACd43E627e64355f1861cEC6d3a6688B31a6F952
    );

    constructor(address _strategy)
        public
        BaseElementYVaultAsset(msg.sender, _strategy, VAULT, DAI)
    {} // solhint-disable no-empty-blocks
}
