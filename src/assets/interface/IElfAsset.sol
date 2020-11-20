pragma solidity >=0.5.8 <0.8.0;

interface IElfAsset {
    function vault() external returns (address);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount, address _sender) external;

    function balance() external view returns (uint256);
}
