// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.7.1;

// A contract who's whole purpose is to not trigger call failure reverts
contract TestVault {
    address public pool;

    function setPool(address _pool) external {
        pool = _pool;
    }

    enum PoolSpecialization {
        GENERAL,
        MINIMAL_SWAP_INFO,
        TWO_TOKEN
    }

    function registerPool(PoolSpecialization) external returns (bytes32) {
        pool = msg.sender;
        return (bytes32)("0x00");
    }

    /* solhint-disable no-empty-blocks */
    function registerTokens(
        bytes32,
        address[] memory,
        address[] memory
    ) external {}

    /* solhint-enable no-empty-blocks */

    // This fallback allows us to make an arbitrary call with this vault as the msg.sender
    // solhint-disable-next-line payable-fallback
    fallback() external {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            calldatacopy(0, 0, calldatasize())
            let succeeded := call(
                gas(),
                sload(pool.slot),
                callvalue(),
                0,
                calldatasize(),
                0,
                0
            )

            if iszero(succeeded) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returndatacopy(0, 0, returndatasize())
            return(0, returndatasize())
        }
    }
}
