// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "../vault/interfaces/IVault.sol";
import "../vault/interfaces/IBasePool.sol";

abstract contract BasePoolFactory {
    IVault public immutable vault;

    uint256 private _pools;

    event PoolCreated(address indexed pool);

    constructor(IVault _vault) {
        vault = _vault;
    }

    /**
     * @dev Deploys a pool contract defined by `creationCode`.
     *
     * The creation code for a Solidity contract can be constructed by concatenating the `creationCode` property of the
     * contract type with the ABI-encoded constructor arguments. Note that the compiler doesn't perform any type
     * checking here: all factory-created contracts should be subject to at least basic testing.
     *
     * Sample usage using abi.encodePacked to concatenate the `bytes` arrays:
     *   _create(abi.encodePacked(type(ERC20).creationCode, abi.encode("My Token", "TKN", 18)));
     *
     * Emits a `PoolCreated` event.
     *
     * Returns the address of the created contract.
     */
    function _create(bytes memory creationCode) internal returns (address) {
        address pool = Create2.deploy(0, bytes32(_pools++), creationCode);
        emit PoolCreated(pool);
        return pool;
    }
}
