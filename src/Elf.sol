// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./ElfFactoryAuthority.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";

import "./libraries/ERC20Mod.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";

import "./assets/interface/IAssetProxy.sol";

contract Elf is ERC20Mod, ElfFactoryAuthority {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;
    IERC20 public vault;
    IAssetProxy public proxy;

    constructor() public {
        initialize(address(0xcafebabe));
    }

    function initializeElf(
        address _token,
        address _vault,
        address _proxy
    ) external onlyFactory {
        this.initializeToken("ELement Finance", "ELF");
        token = IERC20(_token);
        vault = IERC20(_vault);
        proxy = IAssetProxy(_proxy);
    }

    // This tells us how many vault tokens the pool owns
    function balance() external view returns (uint256) {
        return vault.balanceOf(address(this));
    }

    // This tells us how many of the underlying tokens the pool owns which are in the vault
    function balanceUnderlying() external view returns (uint256) {
        return proxy.underlying(vault.balanceOf(address(this)));
    }

    // Get the amount of the underlying asset a certain amount of shares is worth
    function getSharesToUnderlying(uint256 shares)
        external
        view
        returns (uint256)
    {
        return proxy.underlying(shares);
    }

    function deposit(address sender, uint256 amount) external {
        // Send tokens to the proxy
        token.safeTransferFrom(sender, address(proxy), amount);

        // Trigger deposit and calc how many shares we got from the deposit
        uint256 _before = vault.balanceOf(address(this));
        proxy.deposit();
        uint256 _shares = vault.balanceOf(address(this)).sub(_before);

        // We now have vault tokens equal to the users share
        _mint(sender, _shares);
    }

    function withdraw(address sender, uint256 shares) external {
        // Burn users ELF shares
        _burn(sender, shares);

        // Withdraw that many shares from the vault
        vault.safeTransfer(address(proxy), shares);
        proxy.withdraw();

        token.safeTransfer(sender, token.balanceOf(address(this)));
    }
}
