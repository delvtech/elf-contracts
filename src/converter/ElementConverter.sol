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
            if (_isAlloc) {
                getLoan(_from, _to, _amount, _sender);
            } else {
                // TODO: The decision to repay loan or swap for base assets will eventually need
                // to be decided based on the target collateralization ratio, gas fees, etc.
                // For now, we just settle the loan and swap for anything that is leftover.
                uint256 _leftover = settleLoan(_from, _to, _amount, _sender);
                // TODO: write test for case when there is not enough collateral left to
                // complete withdraw and the remaining assets must be swapped for eth
                if (_leftover > 0) {
                    swap(_from, _to, _amount, _sender);
                }
            }
        } else if (_converterType == 1) {
            swap(_from, _to, _amount, _sender);
        }
    }

    function getLoan(
        address _from, // eth
        address _to, // asset
        uint256 _amount,
        address _sender
    ) internal {
        IERC20(_from).safeTransfer(lender, _amount);
        IElementLender(lender).deposit(_from, _amount, _sender);
        IElementLender(lender).borrow(_to, _amount, 0, _sender);
    }

    function settleLoan(
        address _from, // asset
        address _to, // eth
        uint256 _amount,
        address _sender
    ) internal returns (uint256) {
        uint256 _totalLoanAmount = IElementLender(lender).balanceOf() *
            IElementLender(lender).getLendingPrice(_from, _to);
        uint256 _repayAmount = 0;
        uint256 _diff = 0;
        if (_amount <= _totalLoanAmount) {
            _repayAmount = _amount;
        } else {
            _repayAmount = _totalLoanAmount;
            _diff = _amount.sub(_totalLoanAmount);
        }
        IERC20(_from).safeTransfer(lender, _repayAmount);
        IElementLender(lender).repay(_from, _repayAmount, _sender);
        IElementLender(lender).withdraw(_to, _repayAmount, _sender);
        return _diff;
    }

    function swap(
        address _from,
        address _to,
        uint256 _amount,
        address _sender
    ) internal {
        // TODO: implement swapper interface and test implementation
        IERC20(_from).safeTransfer(swapper, _amount);
    }

    function balanceOf() public view returns (uint256) {
        return
            weth.balanceOf(address(this)).add(
                IElementLender(lender).balanceOf()
            );
    }
}
