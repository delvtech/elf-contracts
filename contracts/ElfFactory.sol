// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./Elf.sol";
import "./assets/interface/IAssetProxy.sol";

/// @author Element Finance
/// @title Elf Factory
/// @dev contract is due for a rewrite
contract ElfFactory {
    event NewPool(address indexed caller, address indexed pool);

    mapping(address => bool) private _isPool;

    /// @notice verified if an address is an Elf Pool
    /// @param _p the address to verify
    /// @return boolean of whether or not it is a pool
    function isPool(address _p) external view returns (bool) {
        return _isPool[_p];
    }

    /// @notice make a new Elf pool
    /// @param _token the underlying token for an Elf Core contract
    /// @param _proxy the proxy address for the vault
    /// @return the address of the new Elf pool contract
    function newPool(
        address _token,
        address _proxy,
        string memory _name,
        string memory _symbol
    ) external returns (Elf) {
        IAssetProxy proxy = IAssetProxy(_proxy);
        Elf pool = new Elf(
            _token,
            proxy.vault(),
            address(proxy),
            _name,
            _symbol
        );
        pool.setGovernance(msg.sender);
        _isPool[address(pool)] = true;
        emit NewPool(msg.sender, address(pool));
        return pool;
    }
}
