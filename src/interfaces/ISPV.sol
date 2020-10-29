pragma solidity >=0.5.8 <0.8.0;

interface ISPV {
    function depositAndBorrow(uint256) external;

    function repayAndWithdraw(uint256) external;

    function balances() external view returns (uint256);

    function liabilities() external view returns (uint256);
}
