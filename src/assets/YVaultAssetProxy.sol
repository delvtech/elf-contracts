// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "../ElfFactoryAuthority.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVaultV1.sol";
import "../interfaces/IBPool.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract YVaultAssetProxy is ElfFactoryAuthority {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;
    YearnVault public vault;

    address public pool;
    address public acl;

    // address to redeposit vault shares
    address public secondary;

    function initializeProxy(
        address _vault,
        address _token,
        address _pool
    ) external onlyFactory {
        acl = msg.sender;
        pool = _pool;
        vault = YearnVault(_vault);
        token = IERC20(_token);
        token.approve(_vault, uint256(-1));
    }

    function deposit() external {
        require(msg.sender == pool, "!pool");

        vault.deposit(token.balanceOf(address(this)));
        vault.transfer(pool, vault.balanceOf(address(this)));
    }

    function withdraw() external {
        require(msg.sender == pool, "!pool");

        vault.withdraw(vault.balanceOf(address(this)));
        token.safeTransfer(pool, token.balanceOf(address(this)));
    }

    function underlying(uint256 amount) external view returns (uint256) {
        return vault.getPricePerFullShare().mul(amount).div(1e18);
    }

    function approve() external {
        token.approve(address(vault), 0);
        token.approve(address(vault), uint256(-1));
    }
}
