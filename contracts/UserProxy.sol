// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Permit.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IWETH.sol";
import "./libraries/Authorizable.sol";

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
    address internal immutable trancheFactory;
    // Tranche bytecode hash for Tranche contract address derivation.
    // This is constant as long as Tranche does not implement non-constant constructor arguments.
    bytes32 internal immutable trancheBytecodeHash;
    // A constant which represents ether
    address constant ETH_CONSTANT = address(
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    );

    /// @dev Marks the msg.sender as authorized and sets them
    ///      as the owner in authorization library
    /// @param _weth The constant weth contract address
    /// @param _trancheFactory Address of the TrancheFactory contract
    /// @param _trancheBytecodeHash Hash of the Tranche bytecode.
    constructor(
        IWETH _weth,
        address _trancheFactory,
        bytes32 _trancheBytecodeHash
    ) Authorizable() {
        _authorize(msg.sender);
        weth = _weth;
        trancheFactory = _trancheFactory;
        trancheBytecodeHash = _trancheBytecodeHash;
    }

    /// @dev Requires that the contract is not frozen
    modifier notFrozen() {
        require(!isFrozen, "Contract frozen");
        _;
    }

    /// @dev Allows an authorized address to freeze or unfreeze this contract
    /// @param newState True for frozen and false for unfrozen
    function setIsFrozen(bool newState) external onlyAuthorized() {
        isFrozen = newState;
    }

    /// @dev Mints a principal/interest token pair from either underlying token or Eth
    ///      then returns the tokens to the caller. This function assumes
    ///      that it already has an allowance for the token in question.
    /// @param amount The amount of underlying to turn into tokens
    /// @param underlying Either (1) The underlying ERC20 token contract
    ///                   or (2) the ETH_CONSTANT to indicate the user has sent eth.
    /// @param expiration The expiration time of the Tranche contract
    /// @param position The contract which manages pooled deposits
    function mint(
        uint256 amount,
        IERC20 underlying,
        uint256 expiration,
        address position
    ) external payable notFrozen() {
        // If the underlying token matches this predefined 'ETH token'
        // then we create weth for the user and go from there
        if (address(underlying) == ETH_CONSTANT) {
            // Check that the amount matches the amount provided
            require(msg.value == amount, "Incorrect amount provided");
            // Create weth from the provided eth
            // NOTE - This can be made slightly cheaper by depositing 1 wei into this
            //        contract address on weth.
            weth.deposit{ value: msg.value }();
            weth.transfer(address(position), amount);
            // Proceed to internal minting steps
            _mint(expiration, position);
        } else {
            // Move the user's funds to the wrapped position contract
            underlying.transferFrom(msg.sender, address(position), amount);
            // Proceed to internal minting steps
            _mint(expiration, position);
        }
    }

    /// @dev Mints a principal/Interest token pair from a underlying token which supports
    ///      the permit method. This call sets the allowance on this contract
    ///      for the underlying ERC20 token to be unlimited and expects the
    ///      signature to have an expiration time of uint256.max
    /// @param amount The amount of underlying to turn into tokens
    /// @param underlying The underlying ERC20 token contract
    /// @param expiration The expiration time of the Tranche contract
    /// @param position The contract which manages pooled positions
    /// @param v The bit indicator which allows address recover from signature
    /// @param r The r component of the signature.
    /// @param s The s component of the signature.
    function mintPermit(
        uint256 amount,
        IERC20Permit underlying,
        uint256 expiration,
        address position,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external notFrozen() {
        // Permit this contract to have unlimited access to
        // the msg.sender's funds
        underlying.permit(
            msg.sender,
            address(this),
            type(uint256).max,
            type(uint256).max,
            v,
            r,
            s
        );
        // Move the user's funds to the wrapped position contract
        underlying.transferFrom(msg.sender, address(position), amount);
        // Pass call to internal function which works once approved
        _mint(expiration, position);
    }

    /// @dev This internal mint function preforms the core minting logic after
    ///      the contract has already transferred to WrappedPosition contract
    /// @param expiration The tranche expiration time
    /// @param position The contract which interacts with the yield bering strategy
    function _mint(uint256 expiration, address position) internal {
        // Use create2 to derive the tranche contract
        ITranche tranche = _deriveTranche(address(position), expiration);
        // Move funds into the Tranche contract
        // it will credit the msg.sender with the new tokens
        tranche.prefundedDeposit(msg.sender);
    }

    /// @dev This internal function produces the deterministic create2
    ///      address of the Tranche contract from an wrapped position contract and expiration
    /// @param position The wrapped position contract address
    /// @param expiration The expiration time of the tranche
    /// @return The derived Tranche contract
    function _deriveTranche(address position, uint256 expiration)
        internal
        virtual
        view
        returns (ITranche)
    {
        bytes32 salt = keccak256(abi.encodePacked(position, expiration));
        bytes32 addressBytes = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                trancheFactory,
                salt,
                trancheBytecodeHash
            )
        );
        return ITranche(address(uint160(uint256(addressBytes))));
    }
}
