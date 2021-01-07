// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./Elf.sol";
import "./CloneFactory.sol";
import "./assets/interface/IAssetProxy.sol";
import "./assets/YVaultAssetProxy.sol";

contract ElfFactory is CloneFactory {
    address public masterAssetProxy;
    address public masterElf;

    event PoolCloneCreated(
        address indexed caller,
        address indexed pool
    );

    mapping(address => bool) private _isPool;

    constructor(address _masterAssetProxy, address _masterElf) public {
        masterAssetProxy = _masterAssetProxy;
        masterElf = _masterElf;
    }

    function isPool(address p) external view returns (bool) {
        return _isPool[p];
    }

    function newPool(address token, address vault) external returns (Elf) {
        address proxyClone = createClone(masterAssetProxy);
        address elfClone = createClone(masterElf);
        YVaultAssetProxy proxy = YVaultAssetProxy(proxyClone);
        Elf pool = Elf(elfClone);

        proxy.initialize(address(this));
        proxy.initializeProxy(vault, token, elfClone);

        pool.initialize(address(this));
        pool.initializeElf(token, address(proxy.vault()), proxyClone);

        _isPool[address(pool)] = true;
        emit PoolCloneCreated(msg.sender, elfClone);
        return pool;
    }
}
