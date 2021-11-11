// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IYearnVault.sol";
import "../libraries/Authorizable.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ITranche.sol";

contract ZapYearnShares is Authorizable {
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

    /// @notice Mints a Principal/Interest token pair from yearn vault shares.
    ///      then returns the tokens to the caller.
    /// @param _underlying The underlying ERC20 token contract of the yearn vault.
    /// @param _vault The address of the target yearn vault.
    /// @param _amount The amount of yearn shares to turn into tokens
    /// @param _expiration The expiration time of the Tranche contract.
    /// @param _position The contract which manages pooled deposits.
    /// @param _ptExpected The minimum amount of principal tokens to mint.
    /// @return returns the minted amounts of principal and yield tokens (PT and YT)
    function zapSharesIn(
        IERC20 _underlying,
        IYearnVault _vault,
        uint256 _amount,
        uint256 _expiration,
        address _position,
        uint256 _ptExpected
    ) external notFrozen returns (uint256, uint256) {
        _vault.transferFrom(msg.sender, address(this), _amount);
        _vault.withdraw(_amount, _position, 0);

        ITranche tranche = _deriveTranche(address(_position), _expiration);
        uint256 balance = _underlying.balanceOf(_position);

        (uint256 ptMinted, uint256 ytMinted) = tranche.prefundedDeposit(
            msg.sender
        );
        require(ytMinted >= balance, "Not enough YT minted");
        require(ptMinted >= _ptExpected, "Not enough PT minted");
        return (ptMinted, ytMinted);
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

    /// @dev This contract can hold yearn vault share allowances for addresses so if it is deprecated
    ///      it should be removed so that users do not have to remove allowances.
    ///      Note - onlyOwner is a stronger check than onlyAuthorized, many addresses can be
    ///      authorized to freeze or unfreeze the contract but only the owner address can kill
    function deprecate() external onlyOwner {
        selfdestruct(payable(msg.sender));
    }
}
