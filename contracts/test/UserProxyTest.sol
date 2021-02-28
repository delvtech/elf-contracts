pragma solidity ^0.8.0;

import "../UserProxy.sol";
import "../interfaces/IWETH.sol";

// This contract is a user proxy which works for a single
// elf tranche pair
contract UserProxyTest is UserProxy {
    address public immutable tranche;

    constructor(address _weth, address _tranche) UserProxy(IWETH(_weth)) {
        tranche = _tranche;
    }

    // solhint-disable-next-line private-vars-leading-underscore
    function deriveTranche(address elf, uint256 expiration)
        internal
        override
        view
        returns (ITranche)
    {
        return ITranche(tranche);
    }
}
