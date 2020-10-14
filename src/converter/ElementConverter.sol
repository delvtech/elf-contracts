pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "../lenders/interface/IElementLender.sol";

contract ElementConverter {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public weth;
    address public governance;
    address public lender;
    address public swapper;

    constructor(address _weth) public {
        governance = msg.sender;
        weth = IERC20(_weth);
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setLender(address _lender) public {
        require(msg.sender == governance, "!governance");
        lender = _lender;
    }

    function setSwapper(address _swapper) public {
        require(msg.sender == governance, "!governance");
        swapper = _swapper;
    }

    function convert(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _converterType,
        bool _isAlloc,
        address _sender
    ) external {
        if (_converterType == 0) {
            IERC20(_from).safeTransfer(lender, _amount);
            if (_isAlloc) {
                IElementLender(lender).deposit(_from, _amount, _sender);
                IElementLender(lender).borrow(_to, _amount, 0, _sender);
            } else {
                IElementLender(lender).repay(_from, _amount, _sender);
                IElementLender(lender).withdraw(_to, _amount, _sender);
            }
        } else if (_converterType == 1) {
            // swap
        }
    }

    function balanceOf() public view returns (uint256) {
        return
            weth.balanceOf(address(this)).add(
                IElementLender(lender).balanceOf()
            );
    }
}
