// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.8 <0.8.0;

interface IElfAllocator {
    function setGovernance(address _governance) external;

    function setConverter(address _converter) external;

    function setPriceOracle(address _priceOracle) external;

    function setAllocations(
        address[] calldata _fromToken,
        address[] calldata _toToken,
        address[] calldata _lenders,
        uint256[] calldata _percents,
        address[] calldata _asset,
        uint256 _numAllocations
    ) external;

    function getNumAllocations() external view returns (uint256);

    function getAllocations()
        external
        view
        returns (
            address[] memory,
            address[] memory,
            address[] memory,
            uint256[] memory,
            address[] memory,
            uint256
        );

    function allocate(uint256 _amount) external;

    function deallocate(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function balance() external;
}
