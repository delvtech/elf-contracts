// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

interface IAssetProxy {
    function vault() external view returns (address);

    function deposit() external;

    function withdraw() external;

    function underlying(uint256) external view returns (uint256);
}
