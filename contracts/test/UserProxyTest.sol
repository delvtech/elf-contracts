pragma solidity ^0.8.0;

import "../UserProxy.sol";
import "../interfaces/IWETH.sol";

// This contract is a user proxy which works for a single
// elf tranche pair
contract UserProxyTest is UserProxy {
    constructor(
        address _weth,
        address _trancheFactory,
        bytes32 _trancheBytecodeHash
    ) UserProxy(IWETH(_weth), _trancheFactory, _trancheBytecodeHash) {}

    // solhint-disable-next-line private-vars-leading-underscore
    function deriveTranche(address elf, uint256 expiration)
        public
        view
        returns (ITranche)
    {
        return _deriveTranche(elf, expiration);
    }
}
