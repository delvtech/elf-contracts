pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract ALender {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 weth;
    address public converter;

    constructor(address _converter, address _weth) public {
        converter = _converter;
        weth = IERC20(_weth);
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
        IERC20(_reserve).safeTransfer(_sender, _amount);
    }

    function withdraw(
        address _reserve,
        uint256 _amount,
        address _sender
    ) external {
        require(msg.sender == converter, "!converter");
        IERC20(_reserve).safeTransfer(_sender, _amount);
    }

    function balanceOf() public view returns (uint256) {
        return weth.balanceOf(address(this));
    }

    // to be able to receive funds
    fallback() external payable {}
}
