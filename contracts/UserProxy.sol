// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Permit.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IWETH.sol";
import "./libraries/Authorizable.sol";

/// @author Element Finance
/// @title User Proxy
contract UserProxy is Authorizable {
    // This contract is a convenience library to consolidate
    // the actions needed to create interest or principal tokens to one call.
    // It will hold user allowances, and can be disabled by authorized addresses
    // for security.
    // If frozen users still control their own tokens so can manually redeem them.

    // Store the accessibility state of the contract
    bool public isFrozen = false;
    // Constant wrapped ether address
    IWETH public immutable weth;
    // Tranche factory address for Tranche contract address derivation
    address internal immutable _trancheFactory;
    // Tranche bytecode hash for Tranche contract address derivation.
    // This is constant as long as Tranche does not implement non-constant constructor arguments.
    bytes32 internal immutable _trancheBytecodeHash;
    // A constant which represents ether
    address internal constant _ETH_CONSTANT = address(
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    );

    /// @dev Marks the msg.sender as authorized and sets them
    ///      as the owner in authorization library
    /// @param _weth The constant weth contract address
    /// @param __trancheFactory Address of the TrancheFactory contract
    /// @param __trancheBytecodeHash Hash of the Tranche bytecode.
    constructor(
        IWETH _weth,
        address __trancheFactory,
        bytes32 __trancheBytecodeHash
    ) Authorizable() {
        _authorize(msg.sender);
        weth = _weth;
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
    function setIsFrozen(bool _newState) external onlyAuthorized() {
        isFrozen = _newState;
    }

    /// @notice Mints a Principal/Interest token pair from either underlying token or Eth
    ///      then returns the tokens to the caller.
    /// @dev This function assumes that it already has an allowance for the token in question.
    /// @param _amount The amount of underlying to turn into tokens
    /// @param _underlying Either (1) The underlying ERC20 token contract
    ///                   or (2) the _ETH_CONSTANT to indicate the user has sent eth.
    ///                   This token should revert in the event of a transfer failure.
    /// @param _expiration The expiration time of the Tranche contract
    /// @param _position The contract which manages pooled deposits
    function mint(
        uint256 _amount,
        IERC20 _underlying,
        uint256 _expiration,
        address _position
    ) external payable notFrozen() {
        // If the underlying token matches this predefined 'ETH token'
        // then we create weth for the user and go from there
        if (address(_underlying) == _ETH_CONSTANT) {
            // Check that the amount matches the amount provided
            require(msg.value == _amount, "Incorrect amount provided");
            // Create weth from the provided eth
            // NOTE - This can be made slightly cheaper by depositing 1 wei into this
            //        contract address on weth.
            weth.deposit{ value: msg.value }();
            weth.transfer(address(_position), _amount);
            // Proceed to internal minting steps
            _mint(_expiration, _position);
        } else {
            // Move the user's funds to the wrapped position contract
            _underlying.transferFrom(msg.sender, address(_position), _amount);
            // Proceed to internal minting steps
            _mint(_expiration, _position);
        }
    }

    /// @notice Mints a Principal/Interest token pair from a underlying token which supports
    ///      the permit method.
    /// @dev This call sets the allowance on this contract
    ///      for the underlying ERC20 token to be unlimited and expects the
    ///      signature to have an expiration time of uint256.max
    /// @param _amount The amount of underlying to turn into tokens
    /// @param _underlying The underlying ERC20 token contract
    /// @param _expiration The expiration time of the Tranche contract
    /// @param _position The contract which manages pooled positions
    /// @param _v The bit indicator which allows address recover from signature
    /// @param _r The r component of the signature.
    /// @param _s The s component of the signature.
    function mintPermit(
        uint256 _amount,
        IERC20Permit _underlying,
        uint256 _expiration,
        address _position,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external notFrozen() {
        // Permit this contract to have unlimited access to
        // the msg.sender's funds
        _underlying.permit(
            msg.sender,
            address(this),
            type(uint256).max,
            type(uint256).max,
            _v,
            _r,
            _s
        );
        // Move the user's funds to the wrapped position contract
        _underlying.transferFrom(msg.sender, address(_position), _amount);
        // Pass call to internal function which works once approved
        _mint(_expiration, _position);
    }

    /// @dev This internal mint function performs the core minting logic after
    ///      the contract has already transferred to WrappedPosition contract
    /// @param _expiration The tranche expiration time
    /// @param _position The contract which interacts with the yield bearing strategy
    function _mint(uint256 _expiration, address _position) internal {
        // Use create2 to derive the tranche contract
        ITranche tranche = _deriveTranche(address(_position), _expiration);
        // Move funds into the Tranche contract
        // it will credit the msg.sender with the new tokens
        tranche.prefundedDeposit(msg.sender);
    }

    /// @dev This internal function produces the deterministic create2
    ///      address of the Tranche contract from a wrapped position contract and expiration
    /// @param _position The wrapped position contract address
    /// @param _expiration The expiration time of the tranche
    /// @return The derived Tranche contract
    function _deriveTranche(address _position, uint256 _expiration)
        internal
        virtual
        view
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

    /// @dev This contract holds a number of allowances for addresses so if it is deprecated
    ///      it should be removed so that users do not have to remove allowances.
    ///      Note - onlyOwner is a stronger check than onlyAuthorized, many addresses can be
    ///      authorized to freeze or unfreeze the contract but only the owner address can kill
    function deprecate() external onlyOwner() {
        selfdestruct(payable(msg.sender));
    }
}
