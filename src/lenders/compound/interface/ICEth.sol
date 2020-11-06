pragma solidity >=0.5.8 <0.8.0;

import "./ICToken.sol";

interface ICEth is ICToken {
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function liquidateBorrow(address borrower, ICToken cTokenCollateral) external payable;
    function mint() external payable;
}