pragma solidity >=0.5.8 <0.8.0;

interface IElementLender {
    function deposit(
        address _reserve,
        uint256 _amount,
        address _sender
    ) external payable;

    function borrow(
        address _reserve,
        uint256 _amount,
        uint256 _interestRateModel,
        address _sender
    ) external;

    function repay(
        address _reserve,
        uint256 _amount,
        address _sender
    ) external;

    function withdraw(
        address _reserve,
        uint256 _amount,
        address _sender
    ) external;

    function getLendingPrice(address fromToken, address toToken)
        external
        view
        returns (uint256);

    function balanceOf() external view returns (uint256);
}
