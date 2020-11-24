// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../pools/low/interface/IElf.sol";
import "../pools/low/interface/IElfAllocator.sol";

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

    function getPoolBalance(address payable _pool)
        external
        view
        returns (uint256)
    {
        return IElf(_pool).balance();
    }

    function getPoolAPY(address payable _pool) external pure returns (uint256) {
        require(_pool != address(0));
        return 125 * 10**18;
    }

    function getNumPoolAllocations(address payable _pool)
        external
        view
        returns (uint256)
    {
        return IElfAllocator(IElf(_pool).getAllocator()).getNumAllocations();
    }

    function getPoolAllocations(address payable _pool)
        external
        view
        returns (
            address[] memory,
            address[] memory,
            address[] memory,
            uint256[] memory,
            address[] memory,
            uint256
        )
    {
        return IElfAllocator(IElf(_pool).getAllocator()).getAllocations();
    }
}
