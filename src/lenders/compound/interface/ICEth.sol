pragma solidity >=0.5.8 <0.8.0;

import "./ICToken.sol";

interface ICEth is ICToken {
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function liquidateBorrow(address borrower, ICToken cTokenCollateral)
        external
        payable;

    function mint() external payable;
}
