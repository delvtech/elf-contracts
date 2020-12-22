// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./Elf.sol";
import "./assets/interface/IAssetProxy.sol";

contract ElfFactory {
    event NewPool(address indexed caller, address indexed pool);

    mapping(address => bool) private _isPool;

    function isPool(address p) external view returns (bool) {
        return _isPool[p];
    }

    function newPool(address token, address proxy) external returns (Elf) {
        IAssetProxy _proxy = IAssetProxy(proxy);
        Elf _pool = new Elf(token, _proxy.vault(), address(_proxy));
        _pool.setGovernance(msg.sender);
        _isPool[address(_pool)] = true;
        emit NewPool(msg.sender, address(_pool));
        return _pool;
    }
}
