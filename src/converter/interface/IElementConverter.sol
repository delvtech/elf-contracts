pragma solidity >=0.5.8 <0.8.0;

interface IElementConverter {
    function convert(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _conversionType,
        uint256 _implementation,
        address _sender
    ) external;

    function balanceOf() external view returns (uint256);
}
