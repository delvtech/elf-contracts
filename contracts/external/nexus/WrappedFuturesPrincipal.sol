// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

import { ERC20PermitWithSupply, ERC20Permit } from "../../libraries/ERC20PermitWithSupply.sol";
import { Authorizable } from "../../libraries/Authorizable.sol";
import { ITranche } from "../../interfaces/ITranche.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract WrappedFuturesPrincipal is ERC20PermitWithSupply, Authorizable {

    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // Address of the base/underlying token which is used to buy the yield bearing token from the wrapped position.
    // Ex - LUSD is used to buy the Curve LUSD v2 yield bearing token
    address public immutable baseToken;

    // Enumerable address list, It contains the list of allowed tranches that are insured by this contract
    // Criteria to choose the tranches are - 
    // a). Tranche should have same underlying/base token (i.e ETH, BTC, USDC).
    // b). Should have the similar risk profiles.
    EnumerableSet.AddressSet private _allowedTranches;

    // Emitted when new tranche get whitelisted.
    event TrancheAdded(address _tranche);

    /// @notice Modifier to validate the tranche is whitelisted or not.
    modifier isValidTranche(address _tranche) {
        require(isAllowedTranche(_tranche), "WFP:ALREADY_EXISTS");
        _;
    }
    
    ///@notice Initialize the wrapped token.
    ///@dev    Wrapped token have 18 decimals, It is independent of the baseToken decimals.
    constructor(address baseToken_, address owner_)
     ERC20Permit(
        _processName(IERC20Metadata(baseToken_).symbol()),
        _processSymbol(IERC20Metadata(baseToken_).symbol())
    ) {
        baseToken = baseToken_;
        _authorize(owner_);
        setOwner(owner_);
    }

    ///@notice Allows to create the name for the wrapped token.
    function _processName(string memory _tokenSymbol) internal pure returns(string memory) {
        return string(abi.encodePacked("Wrapped", _tokenSymbol, "Futures Principal"));
    }

    ///@notice Allows to create the symbol for the wrapped token.
    function _processSymbol(string memory _tokenSymbol) internal pure returns(string memory) {
        return string(abi.encodePacked("ep:","W",_tokenSymbol));
    }


    /// @notice Add tranches within the allowed tranches enumerable set.
    /// @dev    It is only allowed to execute by the owner of the contract.
    ///         Tranches which has underlying token equals to the base token are
    ///         only allowed to add, Otherwise it will revert.
    /// @param  _tranche Address of the tranche which needs to add.
    function addTranche(address _tranche) external isValidTranche(_tranche) onlyOwner {
        require(address(ITranche(_tranche).underlying()) == baseToken, "WFP:INVALID_TRANCHE");
        _allowedTranches.add(_tranche);
        emit TrancheAdded(_tranche);
    }

    /// @notice Allows the defaulter to mint wrapped tokens (Insured position) by
    ///         sending the de-pegged token to the contract.
    /// @dev    a) Only allow minting the insured position when the tranche got expired otherwise revert.
    ///         b) Sufficient allowance of the principal token (i.e tranche) should be provided
    ///            to the contract by the `msg.sender` to make execution successful.
    /// @param  _amount Amount of insured position / wrapped token `msg.sender` wants to mint.
    /// @param  _tranche Address of the tranche which is insured by this insured position contract / wrapped token.
    function mint(uint256 _amount, address _tranche) external isValidTranche(_tranche) {
        // Only allow minting when the position get expired.
        require(ITranche(_tranche).unlockTimestamp() < block.timestamp, "WFP:POSITION_NOT_EXPIRED");
        // Assumed that msg.sender provides the sufficient approval the contract.
        IERC20(_tranche).safeTransferFrom(msg.sender, address(this), _fromWad(_amount, _tranche));
        // Mint the corresponding wrapped token to the `msg.sender`.
        _mint(msg.sender, _amount);
    }

    /// @notice Tell whether the given `_tranche` is whitelisted or not.
    /// @param  _tranche Address of the tranche.
    /// @return returns boolean, True -> allowed otherwise false.
    function isAllowedTranche(address _tranche) public view returns(bool) {
        return _allowedTranches.contains(_tranche);
    }

    /// @notice Returns the list of tranches that are whitelisted with the contract. 
    ///         Order is not maintained.
    /// @return Array of addresses.
    function allTranches() public view returns(address[] memory) {
        return _allowedTranches.values();
    }

    /// @notice Returns price of the de-pegged token i.e principal token in terms of TBD.
    function getPrice() external view returns(uint256) {
        // ... TODO implementation
        // Need more input from the nexus to validate the requirement.
    }

    /// @notice Converts the decimal precision of given `_amount` to `_tranche` decimal.
    function _fromWad(uint256 _amount, address _tranche) internal view returns(uint256) {
        return _amount * 10 ** IERC20Metadata(_tranche).decimals() / 1e18;
    }

}