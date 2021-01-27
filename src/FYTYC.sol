// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IElf.sol";

import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/ERC20Permit.sol";

import "./assets/YC.sol";

contract FYTYC is ERC20Permit {
    using SafeERC20 for IERC20;
    using Address for address;

    YC public yc;
    IElf public elf;

    // Total underlying value locked in the contract. This
    // does not include interest.
    uint256 internal _valueSupplied;

    // The timestamp when FYTs and YCs can be redeemed.
    uint256 public unlockTimestamp;

    /**
    @param _elfContract The Elf contract to use.
    @param _lockDuration The lock duration (seconds).
     */
    constructor(address _elfContract, uint256 _lockDuration)
        public
        ERC20("Fixed Yield Token", "FYT")
        ERC20Permit("Fixed Yield Token")
    {
        yc = new YC(address(this));
        elf = IElf(_elfContract);
        unlockTimestamp = block.timestamp + _lockDuration;
    }

    /**
    @notice Deposit ELF tokens and receive FYT and YC ERC20 tokens.
            If interest has already been accrued by the
            ELF tokens held in this contract, the number
            of FYT tokens minted is reduced in order to pay for the accrued interest.
    @param _shares The number of ELF tokens to deposit.
     */
    function deposit(uint256 _shares) external {
        require(block.timestamp < unlockTimestamp, "expired");

        uint256 depositValue = elf.getSharesToUnderlying(_shares) -
            _interestOwed(_shares);
        _valueSupplied = _valueSupplied + depositValue;

        elf.transferFrom(msg.sender, address(this), _shares);
        yc.mint(msg.sender, _shares);
        _mint(msg.sender, depositValue);
    }

    /**
    @notice Burn FYT tokens to withdraw ELF tokens.
    @param _amount The number of FYT tokens to burn.
     */
    function withdrawFyt(uint256 _amount) external {
        require(block.timestamp >= unlockTimestamp, "not expired yet");

        uint256 withdrawable = _underlyingValueLocked() - _currentInterest();
        uint256 owed = (withdrawable * _amount) / totalSupply();

        _valueSupplied = _valueSupplied - owed;

        _burn(msg.sender, _amount);
        elf.transfer(msg.sender, _underlyingToElf(owed));
    }

    /**
    @notice Burn YC tokens to withdraw ELF tokens.
    @param _amount The number of YC tokens to burn.
     */
    function withdrawYc(uint256 _amount) external {
        require(block.timestamp >= unlockTimestamp, "not expired yet");
        uint256 underlyingOwed = (_currentInterest() * _amount) /
            yc.totalSupply();
        yc.burn(msg.sender, _amount);
        elf.transfer(msg.sender, _underlyingToElf(underlyingOwed));
    }

    /**
    @notice Helper. Get the total interest accrued by the locked tokens 
            at any given time. 
     */
    function _currentInterest() internal view returns (uint256) {
        uint256 underlyingValueLocked = _underlyingValueLocked();
        if (
            underlyingValueLocked == 0 || underlyingValueLocked < _valueSupplied
        ) {
            return 0;
        }
        return underlyingValueLocked - _valueSupplied;
    }

    /**
    @notice Helper. Get the total underlying value of all locked ELF tokens.
     */
    function _underlyingValueLocked() internal view returns (uint256) {
        return elf.balanceOfUnderlying(address(this));
    }

    /**
    @notice Helper. Get the ELF value of a given number of underlying tokens. 
     */
    function _underlyingToElf(uint256 _amount) internal view returns (uint256) {
        if (_underlyingValueLocked() == 0) {
            return 0;
        }
        // Each unit of the ELF token has 18 decimals so 1 of them
        // is 1 * 10**18
        return (_amount * 1e18) / elf.getSharesToUnderlying(1e18);
    }

    /**
    @notice Helper. Get the interest owed on a given number of shares deposited. 
    */
    function _interestOwed(uint256 _shares) internal view returns (uint256) {
        if (_underlyingValueLocked() == 0) {
            return 0;
        }
        return (_currentInterest() * _shares) / yc.totalSupply();
    }
}
