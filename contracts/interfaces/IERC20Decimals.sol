pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Decimals is IERC20 {
    // Non standard but almost all erc20 have this
    function decimals() external view returns (uint8);
}
