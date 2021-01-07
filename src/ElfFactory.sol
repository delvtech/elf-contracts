// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./Elf.sol";
import "./assets/interface/IAssetProxy.sol";
import "./assets/YVaultAssetProxy.sol";

contract ElfFactory {

    event NewPool(address indexed caller, address indexed pool);

    mapping(address => bool) private _isPool;

    function isPool(address p) external view returns (bool) {
        return _isPool[p];
    }

    function newPool(address token, address vault) external returns (Elf) {
        YVaultAssetProxy _proxy = new YVaultAssetProxy(vault, token);
        Elf _pool = new Elf(token, address(_proxy.vault()), address(_proxy));
        _proxy.setPool(address(_pool));
        _isPool[address(_pool)] = true;
        emit NewPool(msg.sender, address(_pool));
        return _pool;
    }
}
