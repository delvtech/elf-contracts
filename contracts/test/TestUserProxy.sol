// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../UserProxy.sol";
import "../interfaces/IWETH.sol";

// This contract is a user proxy which exposes deriveTranche for testing
contract TestUserProxy is UserProxy {
    constructor(
        address _weth,
        address _trancheFactory,
        bytes32 _trancheBytecodeHash
    ) UserProxy(IWETH(_weth), _trancheFactory, _trancheBytecodeHash) {} // solhint-disable-line no-empty-blocks

    // solhint-disable-next-line private-vars-leading-underscore
    function deriveTranche(address position, uint256 expiration)
        public
        view
        returns (ITranche)
    {
        return _deriveTranche(position, expiration);
    }
}
