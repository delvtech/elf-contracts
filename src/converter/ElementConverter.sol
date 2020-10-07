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

    constructor() public {
        governance = msg.sender;
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
        uint256 _conversionType,
        uint256 _implementation

    ) external {
        IERC20(_from).safeTransfer(msg.sender, _amount);
        if (_conversionType == 0) {
            loan(_implementation);
        } else if (_conversionType == 1) {
            swap(_implementation);
        }
    
    }

    function swap(uint256 _implementation) internal {

    }

    function loan(uint256 _implementation) internal {

    }
}
