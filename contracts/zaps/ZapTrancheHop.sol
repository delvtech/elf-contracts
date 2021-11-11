// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IYearnVault.sol";
import "../libraries/Authorizable.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ITranche.sol";

contract ZapTrancheHop is Authorizable {
    // Store the accessibility state of the contract
    bool public isFrozen = false;
    // Tranche factory address for Tranche contract address derivation
    address internal immutable _trancheFactory;
    // Tranche bytecode hash for Tranche contract address derivation.
    // This is constant as long as Tranche does not implement non-constant constructor arguments.
    bytes32 internal immutable _trancheBytecodeHash;

    /// @param __trancheFactory Address of the TrancheFactory contract
    /// @param __trancheBytecodeHash Hash of the Tranche bytecode.
    constructor(address __trancheFactory, bytes32 __trancheBytecodeHash)
        Authorizable()
    {
        _authorize(msg.sender);
        _trancheFactory = __trancheFactory;
        _trancheBytecodeHash = __trancheBytecodeHash;
    }

    /// @dev Requires that the contract is not frozen
    modifier notFrozen() {
        require(!isFrozen, "Contract frozen");
        _;
    }

    /// @dev Allows an authorized address to freeze or unfreeze this contract
    /// @param _newState True for frozen and false for unfrozen
    function setIsFrozen(bool _newState) external onlyAuthorized {
        isFrozen = _newState;
    }

    /// @notice Redeems Principal and Yield tokens and deposits the underlying assets received into
    /// a new tranche. The target tranche must use the same underlying asset.
    /// @param _underlying The underlying ERC20 token contract of the yearn vault.
    /// @param _positionFrom The wrapped position of the originating tranche.
    /// @param _expirationFrom The expiration timestamp of the originating tranche.
    /// @param _positionTo The wrapped position of the target tranche.
    /// @param _expirationTo The expiration timestamp of the target tranche.
    /// @param _amountPt Amount of principal tokens to redeem and deposit into the new tranche.
    /// @param _amountYt Amount of yield tokens to redeem and deposit into the new tranche.
    /// @param _ptExpected The minimum amount of principal tokens to mint.
    /// @param _ytExpected The minimum amount of yield tokens to mint.
    /// @return returns the minted amounts of principal and yield tokens (PT and YT)
    function hopToTranche(
        IERC20 _underlying,
        address _positionFrom,
        uint256 _expirationFrom,
        address _positionTo,
        uint256 _expirationTo,
        uint256 _amountPt,
        uint256 _amountYt,
        uint256 _ptExpected,
        uint256 _ytExpected
    ) public notFrozen returns (uint256, uint256) {
        ITranche trancheFrom = _deriveTranche(
            address(_positionFrom),
            _expirationFrom
        );
        ITranche trancheTo = _deriveTranche(
            address(_positionTo),
            _expirationTo
        );

        uint256 balance;
        if (_amountPt > 0) {
            trancheFrom.transferFrom(msg.sender, address(this), _amountPt);
            balance += trancheFrom.withdrawPrincipal(_amountPt, _positionTo);
        }

        if (_amountYt > 0) {
            IERC20 yt = IERC20(trancheFrom.interestToken());
            yt.transferFrom(msg.sender, address(this), _amountYt);
            balance += trancheFrom.withdrawInterest(_amountYt, _positionTo);
        }

        (uint256 ptMinted, uint256 ytMinted) = trancheTo.prefundedDeposit(
            msg.sender
        );

        require(
            ytMinted >= balance && ytMinted >= _ytExpected,
            "Not enough YT minted"
        );
        require(ptMinted >= _ptExpected, "Not enough PT minted");
        return (ptMinted, ytMinted);
    }

    /// @notice There should never be any tokens in this contract.
    /// This function can rescue any possible ERC20 tokens.
    /// @dev This function does not rescue ETH. There is no fallback function so getting
    /// ETH stuck here would be a very deliberate act.
    /// @param token The token to rescue.
    /// @param amount The amount to rescue.
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20 want = IERC20(token);
        want.transfer(msg.sender, amount);
    }

    /// @dev This internal function produces the deterministic create2
    ///      address of the Tranche contract from a wrapped position contract and expiration
    /// @param _position The wrapped position contract address
    /// @param _expiration The expiration time of the tranche
    /// @return The derived Tranche contract
    function _deriveTranche(address _position, uint256 _expiration)
        internal
        view
        virtual
        returns (ITranche)
    {
        bytes32 salt = keccak256(abi.encodePacked(_position, _expiration));
        bytes32 addressBytes = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                _trancheFactory,
                salt,
                _trancheBytecodeHash
            )
        );
        return ITranche(address(uint160(uint256(addressBytes))));
    }
}
