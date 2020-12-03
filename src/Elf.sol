// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";

import "./libraries/ERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";

import "./ElfAllocator.sol";

contract Elf is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public weth;

    address public governance;
    address payable public allocator;

    constructor(address payable _weth) public ERC20("ELement Finance", "ELF") {
        governance = msg.sender;
        weth = IERC20(_weth);
    }

    function balance() external view returns (uint256) {
        return ElfAllocator(allocator).balance();
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setAllocator(address payable _allocator) external {
        require(msg.sender == governance, "!governance");
        allocator = _allocator;
    }

    function getAllocator() external view returns (address payable) {
        return allocator;
    }

    // Get the amount of ETH you will recieve if you were to return X shares to the pool
    function getBalanceUnderlyingPerShare(uint256 shares)
        public
        view
        returns (uint256)
    {
        uint256 balance = ElfAllocator(allocator).balance();
        return shares.mul(balance).div(totalSupply());
    }

    // Get the amount of shares you will recieve if you were to deposit X ETH to the pool
    function getExpectedSharesPerUnderlying(uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 balance = ElfAllocator(allocator).balance();
        return amount.mul(totalSupply()).div(balance);
    }

    function _invest() internal {
        weth.safeTransfer(address(allocator), weth.balanceOf(address(this)));
        ElfAllocator(allocator).allocate(weth.balanceOf(allocator));
    }

    function deposit(uint256 amount) external {
        uint256 _amount = amount;
        uint256 _pool = ElfAllocator(allocator).balance();
        uint256 _shares = 0;
        weth.safeTransferFrom(msg.sender, address(this), _amount);

        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = getExpectedSharesPerUnderlying(_amount);
        }
        _mint(msg.sender, _shares);
        _invest();
    }

    function depositFrom(address sender, uint256 amount) external {
        uint256 _amount = amount;
        uint256 _pool = ElfAllocator(allocator).balance();
        uint256 _shares = 0;
        weth.safeTransferFrom(sender, address(this), _amount);

        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = getExpectedSharesPerUnderlying(_amount);
        }
        _mint(sender, _shares);
        _invest();
    }

    function depositETH() public payable {
        uint256 _pool = ElfAllocator(allocator).balance();
        uint256 _amount = msg.value;
        IWETH(payable(address(weth))).deposit{value: _amount}();
        uint256 _shares = 0;
        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = getExpectedSharesPerUnderlying(_amount);
        }
        _mint(msg.sender, _shares);
        _invest();
    }

    function depositETHFrom(address sender) external payable {
        uint256 _pool = ElfAllocator(allocator).balance();
        uint256 _amount = msg.value;
        IWETH(payable(address(weth))).deposit{value: _amount}();
        uint256 _shares = 0;
        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = getExpectedSharesPerUnderlying(_amount);
        }
        _mint(sender, _shares);
        _invest();
    }

    function withdraw(uint256 _shares) external {
        uint256 r = getBalanceUnderlyingPerShare(_shares);

        _burn(msg.sender, _shares);

        ElfAllocator(allocator).deallocate(r);
        ElfAllocator(allocator).withdraw(r);

        weth.safeTransfer(msg.sender, r);
    }

    function withdrawFrom(address sender, uint256 _shares) external {
        uint256 r = getBalanceUnderlyingPerShare(_shares);

        _burn(sender, _shares);

        ElfAllocator(allocator).deallocate(r);
        ElfAllocator(allocator).withdraw(r);

        weth.safeTransfer(sender, r);
    }

    function withdrawETH(uint256 _shares) external {
        uint256 r = getBalanceUnderlyingPerShare(_shares);

        _burn(msg.sender, _shares);

        ElfAllocator(allocator).deallocate(r);
        ElfAllocator(allocator).withdraw(r);

        IWETH(payable(address(weth))).withdraw(r);
        payable(msg.sender).transfer(r);
    }

    function withdrawETHFrom(address sender, uint256 _shares) external {
        uint256 r = getBalanceUnderlyingPerShare(_shares);

        _burn(sender, _shares);

        ElfAllocator(allocator).deallocate(r);
        ElfAllocator(allocator).withdraw(r);

        IWETH(payable(address(weth))).withdraw(r);
        payable(sender).transfer(r);
    }

    receive() external payable {
        if (msg.sender != address(weth)) {
            depositETH();
        }
    }
}
