// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IElf.sol";

contract ElfProxy {
    function deposit(address payable _pool, uint256 _amount) external {
        IElf(_pool).depositFrom(msg.sender, _amount);
    }

    function depositETH(address payable _pool) external payable {
        IElf(_pool).depositETHFrom{value: msg.value}(msg.sender);
    }

    function withdraw(address payable _pool, uint256 _shares) external {
        IElf(_pool).withdrawFrom(msg.sender, _shares);
    }

    function withdrawETH(address payable _pool, uint256 _shares) external {
        IElf(_pool).withdrawETHFrom(msg.sender, _shares);
    }
}
