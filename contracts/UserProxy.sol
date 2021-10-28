// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Permit.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IWrappedPosition.sol";
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
    address internal constant _ETH_CONSTANT =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

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
    function setIsFrozen(bool _newState) external onlyAuthorized {
        isFrozen = _newState;
    }

    // Memory encoding of the permit data
    struct PermitData {
        IERC20Permit tokenContract;
        address who;
        uint256 amount;
        uint256 expiration;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    /// @dev Takes the input permit calls and executes them
    /// @param data The array which encodes the set of permit calls to make
    modifier preApproval(PermitData[] memory data) {
        // If permit calls are provided we make try to make them
        if (data.length != 0) {
            // We make permit calls for each indicated call
            for (uint256 i = 0; i < data.length; i++) {
                _permitCall(data[i]);
            }
        }
        _;
    }

    /// @dev Makes permit calls indicated by a struct
    /// @param data the struct which has the permit calldata
    function _permitCall(PermitData memory data) internal {
        // Make the permit call to the token in the data field using
        // the fields provided.
        // Security note - This fairly open call is safe because it cannot
        // call 'transferFrom' or other sensitive methods despite the open
        // scope. Do not make more general without security review.
        data.tokenContract.permit(
            msg.sender,
            data.who,
            data.amount,
            data.expiration,
            data.v,
            data.r,
            data.s
        );
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
    /// @param _permitCallData Encoded array of permit calls to make prior to minting
    ///                        the data should be encoded with abi.encode(data, "PermitData[]")
    ///                        each PermitData struct provided will be executed as a call.
    ///                        An example use of this is if using a token with permit like USDC
    ///                        to encode a permit which gives this contract allowance before minting.
    /// @return returns the minted amounts of PT and YT
    // NOTE - It is critical that the notFrozen modifier is listed first so it gets called first.
    function mint(
        uint256 _amount,
        IERC20 _underlying,
        uint256 _expiration,
        address _position,
        PermitData[] calldata _permitCallData
    )
        external
        payable
        notFrozen
        preApproval(_permitCallData)
        returns (uint256, uint256)
    {
        // If the underlying token matches this predefined 'ETH token'
        // then we create weth for the user and go from there
        if (address(_underlying) == _ETH_CONSTANT) {
            // Check that the amount matches the amount provided
            require(msg.value == _amount, "Incorrect amount provided");
            // Create weth from the provided eth
            weth.deposit{ value: msg.value }();
            weth.transfer(address(_position), _amount);
        } else {
            // Check for the fact that this branch should not be payable
            require(msg.value == 0, "Non payable");
            // Move the user's funds to the wrapped position contract
            _underlying.transferFrom(msg.sender, address(_position), _amount);
        }

        // Proceed to internal minting steps
        (uint256 ptMinted, uint256 ytMinted) = _mint(_expiration, _position);
        // This sanity check ensure that at least as much was minted as was transferred
        require(ytMinted >= _amount, "Not enough minted");
        return (ptMinted, ytMinted);
    }

    /// @dev Allows a user to withdraw and unwrap weth in the same transaction
    ///      likely quite a bit more expensive than direct unwrapping but useful
    ///      for those who want to do one tx instead of two
    /// @param _expiration The tranche expiration time
    /// @param _position The contract which interacts with the yield bearing strategy
    /// @param _amountPT The amount of principal token to withdraw
    /// @param _amountYT The amount of yield token to withdraw.
    /// @param _permitCallData Encoded array of permit calls to make prior to withdrawing,
    ///                        should be used to get allowances for PT and YT
    // NOTE - It is critical that the notFrozen modifier is listed first so it gets called first.
    function withdrawWeth(
        uint256 _expiration,
        address _position,
        uint256 _amountPT,
        uint256 _amountYT,
        PermitData[] calldata _permitCallData
    ) external notFrozen preApproval(_permitCallData) {
        // Post the Berlin hardfork this call warms the address so only cost ~100 gas overall
        require(IWrappedPosition(_position).token() == weth, "Non weth token");
        // Only allow access if the user is actually attempting to withdraw
        require(((_amountPT != 0) || (_amountYT != 0)), "Invalid withdraw");
        // Because of create2 we know this code is exactly what is expected.
        ITranche derivedTranche = _deriveTranche(_position, _expiration);

        uint256 wethReceivedPt = 0;
        uint256 wethReceivedYt = 0;
        // Check if we need to withdraw principal token
        if (_amountPT != 0) {
            // If we have to withdraw PT first transfer it to this contract
            derivedTranche.transferFrom(msg.sender, address(this), _amountPT);
            // Then we withdraw that PT with the resulting weth going to this address
            wethReceivedPt = derivedTranche.withdrawPrincipal(
                _amountPT,
                address(this)
            );
        }
        // Check if we need to withdraw yield token
        if (_amountYT != 0) {
            // Post Berlin this lookup only costs 100 gas overall as well
            IERC20Permit yieldToken = derivedTranche.interestToken();
            // Transfer the YT to this contract
            yieldToken.transferFrom(msg.sender, address(this), _amountYT);
            // Withdraw that YT
            wethReceivedYt = derivedTranche.withdrawInterest(
                _amountYT,
                address(this)
            );
        }

        // A sanity check that some value was withdrawn
        if (_amountPT != 0) {
            require((wethReceivedPt != 0), "Rugged");
        }
        if (_amountYT != 0) {
            require((wethReceivedYt != 0), "No yield accrued");
        }
        // Withdraw the ether from weth
        weth.withdraw(wethReceivedPt + wethReceivedYt);
        // Send the withdrawn eth to the caller
        payable(msg.sender).transfer(wethReceivedPt + wethReceivedYt);
    }

    /// @dev The receive function allows WETH and only WETH to send
    ///      eth directly to this contract. Note - It Cannot be assumed
    ///      that this will prevent this contract from having an ETH balance
    receive() external payable {
        require(msg.sender == address(weth));
    }

    /// @dev This internal mint function performs the core minting logic after
    ///      the contract has already transferred to WrappedPosition contract
    /// @param _expiration The tranche expiration time
    /// @param _position The contract which interacts with the yield bearing strategy
    /// @return the principal token yield token returned
    function _mint(uint256 _expiration, address _position)
        internal
        returns (uint256, uint256)
    {
        // Use create2 to derive the tranche contract
        ITranche tranche = _deriveTranche(address(_position), _expiration);
        // Move funds into the Tranche contract
        // it will credit the msg.sender with the new tokens
        return tranche.prefundedDeposit(msg.sender);
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

    /// @dev This contract holds a number of allowances for addresses so if it is deprecated
    ///      it should be removed so that users do not have to remove allowances.
    ///      Note - onlyOwner is a stronger check than onlyAuthorized, many addresses can be
    ///      authorized to freeze or unfreeze the contract but only the owner address can kill
    function deprecate() external onlyOwner {
        selfdestruct(payable(msg.sender));
    }
}
