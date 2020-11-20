pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../pools/low/Elf.sol";
import "../pools/low/ElfAllocator.sol";

contract ElfProxy {
    function deposit(address payable _pool, uint256 _amount) external {
        Elf(_pool).depositFrom(msg.sender, _amount);
    }

    function depositETH(address payable _pool) external payable {
        Elf(_pool).depositETHFrom{value: msg.value}(msg.sender);
    }

    function withdraw(address payable _pool, uint256 _shares) external {
        Elf(_pool).withdrawFrom(msg.sender, _shares);
    }

    function withdrawETH(address payable _pool, uint256 _shares) external {
        Elf(_pool).withdrawETHFrom(msg.sender, _shares);
    }

    function getPoolBalance(address payable _pool)
        external
        view
        returns (uint256)
    {
        return Elf(_pool).balance();
    }

    function getPoolAPY(address payable _pool) external view returns (uint256) {
        return 125 * 10**18;
    }

    function getNumPoolAllocations(address payable _pool)
        external
        view
        returns (uint256)
    {
        return ElfAllocator(Elf(_pool).allocator()).numAllocations();
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
        return ElfAllocator(Elf(_pool).allocator()).getAllocations();
    }
}
