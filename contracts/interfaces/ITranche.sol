// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./IERC20Permit.sol";
import "./IInterestToken.sol";

interface ITranche is IERC20Permit {
    function deposit(uint256 _shares, address destination)
        external
        returns (uint256, uint256);

    function prefundedDeposit(address _destination)
        external
        returns (uint256, uint256);

    function withdrawPrincipal(uint256 _amount, address _destination)
        external
        returns (uint256);

    function withdrawInterest(uint256 _amount, address _destination)
        external
        returns (uint256);

    function interestToken() external view returns (IInterestToken);

    function interestSupply() external view returns (uint128);

    function underlying() external view returns (IERC20);

    function unlockTimestamp() external view returns (uint256);
}
