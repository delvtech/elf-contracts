pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/WETH.sol";
import "./ElfStrategy.sol";

contract Elf is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint public min = 9990;
    uint public constant max = 10000;
    address public governance;
    address public strategy;

    constructor() public ERC20("Element Liquidity Fund","ELF") {
        governance = msg.sender;
    }
 
    function balance() public view returns (uint256) {
        // todo: include strategies balance
        return address(this).balance;
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
        return 0;
    }

    function deposit() public payable {
        uint256 _amount = msg.value;
        uint256 _pool = address(this).balance;
        uint256 _shares = 0;
        if (totalSupply() == 0) {
            _shares = _amount;
            _pool = _amount;
        } else {
            _shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, 1);
        // TODO: eventually this will be called seperately
        //IERC20(address(this)).safeTransfer(strategy, _amount);
        //ElfStrategy(strategy).allocate(_amount);
    }

    function withdraw(uint256 _shares) public {
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint256 b = address(this).balance;
        if (b < r) {
            uint256 _withdraw = r.sub(b);
            //ElfStrategy(strategy).deallocate(_withdraw);
            uint256 _after = address(this).balance;
            uint256 _diff = _after.sub(b);
            // todo: ??
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }
        msg.sender.transfer(r);
    }

    receive() external payable {
        deposit();
    }
}