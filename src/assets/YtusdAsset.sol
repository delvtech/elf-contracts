pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./BaseElementYVaultAsset.sol";

contract YtusdAsset is BaseElementYVaultAsset {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant TUSD = address(
        0xdAC17F958D2ee523a2206206994597C13D831ec7
    );
    address public constant VAULT = address(
        0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a
    );

    constructor(address _strategy)
        public
        BaseElementYVaultAsset(msg.sender, _strategy, VAULT, TUSD)
    {} // solhint-disable no-empty-blocks
}
