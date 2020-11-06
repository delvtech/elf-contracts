pragma solidity >=0.5.8 <0.8.0;

import "./ICToken.sol";

interface ICERC20 is ICToken {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, ICToken cTokenCollateral) external returns (uint);

    function underlying() external returns (address);
}