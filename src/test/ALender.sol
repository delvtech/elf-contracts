pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../oracles/interface/IElementPriceOracle.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract ALender {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 weth;
    address public governance;
    address public converter;
    address public priceOracle;

    constructor(address _converter, address _weth) public {
        governance = msg.sender;
        converter = _converter;
        weth = IERC20(_weth);
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setPriceOracle(address _priceOracle) public {
        require(msg.sender == governance, "!governance");
        priceOracle = _priceOracle;
    }

    function deposit(
        address _reserve,
        uint256 _amount,
        address _sender
    ) external payable {
        require(msg.sender == converter, "!converter");
    }

    function borrow(
        address _reserve,
        uint256 _amount,
        uint256 _interestRateModel,
        address _sender
    ) external {
        require(msg.sender == converter, "!converter");
        // _amount is in weth and we need to borrow in AToken ()
        uint256 _convertedAmount = _amount.mul(
            getLendingPrice(address(weth), _reserve)
        );
        IERC20(_reserve).safeTransfer(_sender, _convertedAmount);
    }

    function repay(
        address _reserve,
        uint256 _amount,
        address _sender
    ) external {
        require(msg.sender == converter, "!converter");
    }

    function withdraw(
        address _reserve,
        uint256 _amount,
        address _sender
    ) external {
        require(msg.sender == converter, "!converter");
        // _amount is in AToken and we need to withdraw _amount in weth
        IERC20(_reserve).safeTransfer(
            _sender,
            _amount.div(getLendingPrice(address(weth), _reserve))
        );
    }

    function getLendingPrice(address fromToken, address toToken)
        public
        view
        returns (uint256)
    {
        return IElementPriceOracle(priceOracle).getPrice(fromToken, toToken);
    }

    function balance() public view returns (uint256) {
        return weth.balanceOf(address(this));
    }

    // to be able to receive funds
    fallback() external payable {}
}
