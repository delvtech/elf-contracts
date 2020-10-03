pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/WETH.sol";
import "./ElfStrategy.sol";

contract ELF is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;
    uint public min = 9990;
    uint public constant max = 10000;
    address public governance;
    address public strategy;

    constructor(address _token) public ERC20("Element Liquidity Fund","ELF")
    {
        token = IERC20(_token);
        governance = msg.sender;
    }
 
    function balance() public view returns (uint256) {
        // todo: include strategies balance
        return token.balanceOf(address(this));
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setStrategy(address _strategy) public {
        require(msg.sender == governance, "!governance");
        strategy = _strategy;
    }

    function available() public view returns (uint) {
        // TODO: implement min/max logic
        return token.balanceOf(address(this));
    }

    function deposit() public payable {
        uint256 _pool = balance();
        uint256 _before = token.balanceOf(address(this));
        uint256 _amount = msg.value;
        WETH(address(token)).deposit.value(_amount)(); 
        uint256 _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
        // TODO: eventually this will be called seperately
        uint _bal = available();
        token.safeTransfer(strategy, _bal);
        ElfStrategy(strategy).allocate(_bal);
    }

    function withdraw(uint256 _shares) public {
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint256 b = token.balanceOf(address(this));
        if (b < r) {
            uint256 _withdraw = r.sub(b);
            ElfStrategy(strategy).deallocate(_withdraw);
            uint256 _after = token.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        WETH(address(token)).withdraw(r);
        address payable sender = msg.sender;
        sender.transfer(r);
    }
}