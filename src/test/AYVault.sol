// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVaultV1.sol";

import "../libraries/ERC20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract AYVault is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public token;
    uint256 internal shares = 1e18;

    constructor(address _token) public ERC20("a ytoken", "yToken") {
        token = _token;
        _mint(msg.sender, 1000000000000000000000);
    }

    function deposit(uint256 _amount) external {
        uint256 _shares = _amount; // calculate shares (currently 1:1)
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount); // pull deposit from sender
        _mint(msg.sender, _shares); // mint shares for sender
    }

    function depositAll() external {
        uint256 _amount = IERC20(token).balanceOf(msg.sender);
        uint256 _shares = _amount; // calculate shares (currently 1:1)
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount); // pull deposit from sender
        _mint(msg.sender, _shares); // mint shares for sender
    }

    function withdraw(uint256 _amount) external {
        uint256 _shares = _amount;
        _burn(msg.sender, _shares);
        IERC20(token).safeTransfer(msg.sender, _amount);
    }

    function withdrawAll() external {
        uint256 _amount = IERC20(token).balanceOf(msg.sender);
        uint256 _shares = _amount; // calculate shares (currently 1:1)
        _burn(msg.sender, _shares);
        IERC20(token).safeTransfer(msg.sender, _amount);
    }

    function getPricePerFullShare() external view returns (uint256) {
        return shares;
    }
}
