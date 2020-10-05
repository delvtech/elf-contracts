pragma solidity >=0.4.22 <0.8.0;

interface WETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);
}