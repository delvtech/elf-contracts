// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./Elf.sol";

contract ElfFactory {
    event LOG_NEW_POOL(
        address indexed caller,
        address indexed pool
    );

    mapping(address=>bool) private _isPool;

    function isPool(address p)
        external view returns (bool)
    {
        return _isPool[p];
    }

    function newPool(address payable _weth)
        external
        returns (Elf)
    {
        Elf _pool = new Elf(_weth);
        ElfAllocator _allocator = new ElfAllocator(address(_pool), _weth);
        _pool.setAllocator(payable(_allocator));
        _pool.setGovernance(msg.sender);
        _allocator.setGovernance(msg.sender);
        _isPool[address(_pool)] = true;
        emit LOG_NEW_POOL(msg.sender, address(_pool));
        return _pool;
    }
}
