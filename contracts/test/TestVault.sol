// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.7;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IConvergentCurvePool } from "../interfaces/IConvergentCurvePool.sol";

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
        return (bytes32)("0x01");
    }

    /* solhint-disable no-empty-blocks */
    function registerTokens(
        bytes32,
        address[] memory,
        address[] memory
    ) external {}

    /* solhint-disable no-empty-blocks */
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            IERC20[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        )
    {
        IConvergentCurvePool pool_ = IConvergentCurvePool(pool);
        uint256[] memory tokenBalances = new uint256[](2);
        IERC20[] memory _tokens = new IERC20[](2);
        _tokens[0] = IERC20(pool_.underlying());
        _tokens[1] = IERC20(pool_.bond());
        tokenBalances[0] = uint256(5);
        tokenBalances[1] = uint256(5);
        lastChangeBlock = 0;
        return (_tokens, tokenBalances, lastChangeBlock);
    }

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
