// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.16;

contract Context {
    constructor() public {} // solhint-disable-line no-empty-blocks

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}
