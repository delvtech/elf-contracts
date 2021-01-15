// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./interfaces/IERC20.sol";

import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";

import "./assets/FYT.sol";
import "./assets/YC.sol";

interface Elf {
    function getSharesToUnderlying(uint256 shares)
        external
        view
        returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract FYTYC {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    FYT public fyt;
    YC public yc;
    Elf public elf;

    // Total underlying value locked in the contract. This
    // does not include interest.
    uint256 internal _valueSupplied;

    // The timestamp when FYTs and YCs can be withdrawn.
    uint256 internal _unlockTimestamp;

    /**
    @param _elfContract The Elf contract to use.
    @param _lockDuration The lock duration (seconds).
     */
    constructor(address _elfContract, uint256 _lockDuration) public {
        fyt = new FYT(address(this));
        yc = new YC(address(this));
        elf = Elf(_elfContract);
        _unlockTimestamp = block.timestamp.add(_lockDuration);
    }

    /**
    @notice Deposit ELF tokens and receive FYT and YC ERC20 tokens.
            If interest has already been accrued by the
            ELF tokens held in this contract, the number
            of FYT tokens minted is reduced in order to pay for the accrued interest.
    @param _shares The number of ELF tokens to deposit.
     */
    function deposit(uint256 _shares) external {
        require(block.timestamp < _unlockTimestamp, "expired");

        uint256 depositValue = elf.getSharesToUnderlying(_shares).sub(
            _interestOwed(_shares)
        );
        _valueSupplied = _valueSupplied.add(depositValue);

        elf.transferFrom(msg.sender, address(this), _shares);
        yc.mint(msg.sender, _shares);
        fyt.mint(msg.sender, depositValue);
    }

    /**
    @notice Burn FYT tokens to withdraw ELF tokens.
    @param _amount The number of FYT tokens to burn.
     */
    function withdrawFyt(uint256 _amount) external {
        require(block.timestamp >= _unlockTimestamp, "not expired yet");

        uint256 withdrawable = _underlyingValueLocked().sub(_currentInterest());
        uint256 owed = withdrawable.mul(_amount).div(fyt.totalSupply());

        _valueSupplied = _valueSupplied.sub(owed);

        fyt.burn(msg.sender, _amount);
        elf.transfer(msg.sender, _underlyingToElf(owed));
    }

    /**
    @notice Burn YC tokens to withdraw ELF tokens.
    @param _amount The number of YC tokens to burn.
     */
    function withdrawYc(uint256 _amount) external {
        require(block.timestamp >= _unlockTimestamp, "not expired yet");
        uint256 underlyingOwed = _currentInterest().mul(_amount).div(
            yc.totalSupply()
        );
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
        return underlyingValueLocked.sub(_valueSupplied);
    }

    /**
    @notice Helper. Get the total underlying value of all locked ELF tokens.
     */
    function _underlyingValueLocked() internal view returns (uint256) {
        return elf.getSharesToUnderlying(elf.balanceOf(address(this)));
    }

    /**
    @notice Helper. Get the ELF value of a given number of underlying tokens. 
     */
    function _underlyingToElf(uint256 _amount) internal view returns (uint256) {
        if (_underlyingValueLocked() == 0) {
            return 0;
        }
        return
            elf.balanceOf(address(this)).mul(_amount).div(
                _underlyingValueLocked()
            );
    }

    /**
    @notice Helper. Get the interest owed on a given number of shares deposited. 
    */
    function _interestOwed(uint256 _shares) internal view returns (uint256) {
        if (_underlyingValueLocked() == 0) {
            return 0;
        }
        return _currentInterest().mul(_shares).div(yc.totalSupply());
    }
}
