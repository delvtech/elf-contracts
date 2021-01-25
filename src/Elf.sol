// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";

import "./libraries/ERC20Permit.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";

import "./assets/interface/IAssetProxy.sol";

/// @author Element Finance
/// @title Elf Core
contract Elf is ERC20Permit {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;
    IERC20 public vault;
    IAssetProxy public proxy;
    address public governance;

    constructor(
        address _token,
        address _vault,
        address _proxy
    ) public ERC20("ELement Finance", "ELF") ERC20Permit("ELement Finance") {
        governance = msg.sender;
        token = IERC20(_token);
        vault = IERC20(_vault);
        proxy = IAssetProxy(_proxy);
    }

    /// @notice Returns how many vault tokens the pool owns
    /// @return balance of vault in vault share tokens
    function balance() external view returns (uint256) {
        return vault.balanceOf(address(this));
    }

    /// @notice Returns how many of the underlying tokens the pool owns which are in the vault
    /// @return balance of vault in underlying asset
    function balanceUnderlying() external view returns (uint256) {
        return proxy.underlying(vault.balanceOf(address(this)));
    }

    /// @notice Get the underlying balance of an address
    /// @param _who The address to query
    /// @return The underlying token balance of the address
    function balanceOfUnderlying(address _who) external view returns (uint256) {
        return proxy.underlying(balanceOf(_who));
    }

    /// @notice Update the governance address
    /// @param _governance new governance address
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    /// @notice Returns the amount of the underlying asset a certain amount of shares is worth
    /// @param _shares to calculate underlying value for
    /// @return the value of underlying assets for the given shares
    function getSharesToUnderlying(uint256 _shares)
        external
        view
        returns (uint256)
    {
        return proxy.underlying(_shares);
    }

    /// @notice Entry point to deposit tokens into the Elf contract
    /// @param _sender the address of the user who is depositing
    /// @param _amount the amount of underlying tokens to deposit
    /// @dev we take the sender here to allow for msg.sender to be a relayer or proxy
    /// @return Returns the number of ELF tokens minted
    function deposit(address _sender, uint256 _amount) external returns(uint256){
        // Send tokens to the proxy
        token.safeTransferFrom(_sender, address(proxy), _amount);

        // Trigger deposit and calc how many shares we got from the deposit
        uint256 before = vault.balanceOf(address(this));
        proxy.deposit();
        uint256 shares = vault.balanceOf(address(this)).sub(before);

        // We now have vault tokens equal to the users share
        _mint(_sender, shares);
        return shares;
    }

    /// @notice Exit point to withdraw tokens from the Elf contract
    /// @param _sender the address of the user who is withdrawing
    /// @param _shares the amount of shares the user is burning to withdraw underlying
    /// @return The amount of underlying transfered to the caller
    function withdraw(address _sender, uint256 _shares) external returns(uint256) {
        // Burn users ELF shares
        _burn(_sender, _shares);

        // Withdraw that many shares from the vault
        vault.safeTransfer(address(proxy), _shares);
        proxy.withdraw();

        uint256 withdrawAmount = token.balanceOf(address(this));
        token.safeTransfer(_sender, withdrawAmount);
        return withdrawAmount;
    }
}
