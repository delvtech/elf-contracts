pragma solidity ^0.8.0;

contract CodeSizeChecker {
    function codeSize(address which) external view returns (uint256 ret) {
        assembly {
            ret := extcodesize(which)
        }
    }
}
