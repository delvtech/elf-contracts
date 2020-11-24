// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.8 <0.8.0;

interface LendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);

    function getLendingPoolCore() external view returns (address);

    function getPriceOracle() external view returns (address);
}
