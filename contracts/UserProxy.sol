// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Permit.sol";
import "./interfaces/IElf.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IWETH.sol";
import "./libraries/Authorizable.sol";

contract UserProxy is Authorizable {
    // This contract is a convenience library to consolidate
    // the actions needed to create FYT/YC to one call.
    // It will hold user allowances, and can be disabled
    // by an owner for security.
    // If frozen users still control their own tokens
    // so can manually redeem them.

    // Store the accessibility state of the contract
    bool public isFrozen = false;
    // Constant wrapped ether address
    IWETH public immutable weth;
    // A constant which represents ether
    address constant ETH_CONSTANT = address(
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    );

    /// @param _weth The constant weth contract address
    /// @dev Marks the msg.sender as authorized and sets them
    ///      as the owner in authorization library
    constructor(IWETH _weth) Authorizable() {
        _authorize(msg.sender);
        weth = _weth;
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

    /// @dev Mints a FYT/YC token pair from either underlying token or Eth
    ///      then returns the FYT YC to the caller. This function assumes
    ///      that it already has an allowance for the token in question.
    /// @param amount The amount of underlying to turn into FYT/YC
    /// @param underlying Either (1) The underlying ERC20 token contract
    ///                   or (2) the ETH_CONSTANT to indicate the user has sent eth.
    /// @param expiration The expiration time of the Tranche contract
    /// @param elf The contract which manages pooled deposits
    function mint(
        uint256 amount,
        IERC20 underlying,
        uint256 expiration,
        address elf
    ) external payable notFrozen() {
        // If the underlying token matches this predefined 'ETH token'
        // then we create weth for the user and go from there
        if (address(underlying) == ETH_CONSTANT) {
            // Check that the amount matches the amount provided
            require(msg.value == amount, "Incorrect amount provided");
            // Create weth from the provided eth
            // NOTE - This can be made slightly cheaper by depositing 1 wei into this
            //        contract address on weth.
            weth.deposit{value: msg.value}();
            weth.transfer(address(elf), amount);
            // Proceed to internal minting steps
            _mint(expiration, elf);
        } else {
            // Move the user's funds to the elf contract
            underlying.transferFrom(msg.sender, address(elf), amount);
            // Proceed to internal minting steps
            _mint(expiration, elf);
        }
    }

    /// @dev Mints a FYT/YC token pair from a underlying token which supports
    ///      the permit method. This call sets the allowance on this contract
    ///      for the underlying ERC20 token to be unlimited and expects the
    ///      signature to have an expiration time of uint256.max
    /// @param amount The amount of underlying to turn into FYT/YC
    /// @param underlying The underlying ERC20 token contract
    /// @param expiration The expiration time of the Tranche contract
    /// @param elf The contract which manages pooled positions
    /// @param v The bit indicator which allows address recover from signature
    /// @param r The r component of the signature.
    /// @param s The s component of the signature.
    function mintPermit(
        uint256 amount,
        IERC20Permit underlying,
        uint256 expiration,
        address elf,
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
        // Move the user's funds to the elf contract
        underlying.transferFrom(msg.sender, address(elf), amount);
        // Pass call to internal function which works once approved
        _mint(expiration, elf);
    }

    /// @dev This internal mint function preforms the core minting logic after
    ///      the contract has already transferred to ELF
    /// @param expiration The tranche expiration time
    /// @param elf The contract which interacts with the yield bering strategy
    function _mint(uint256 expiration, address elf) internal {
        // Use create2 to derive the tranche contract
        ITranche tranche = deriveTranche(address(elf), expiration);
        // Move funds into the Tranche contract
        // it will credit the msg.sender with the new tokens
        tranche.prefundedDeposit(msg.sender);
    }

    /// @dev This internal function produces the deterministic create2
    ///      address of the Tranche contract from an elf contract and expiration
    /// @param elf The ELF contract address
    /// @param expiration The expiration time of the tranche
    /// @return The derived Tranche contract
    function deriveTranche(address elf, uint256 expiration)
        internal
        virtual
        view
        returns (ITranche)
    {
        return ITranche(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    }
}
