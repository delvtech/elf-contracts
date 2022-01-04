// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

import { ERC20PermitWithSupply, ERC20Permit, IERC20Permit } from "../../libraries/ERC20PermitWithSupply.sol";
import { IWrappedPosition } from "../../interfaces/IWrappedPosition.sol";
import { ITranche } from "../../interfaces/ITranche.sol";
import { IWrappedCoveredPrincipalToken } from "./interfaces/IWrappedCoveredPrincipalToken.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @author Element Finance
/// @title WrappedCoveredPrincipalToken
contract WrappedCoveredPrincipalToken is
    ERC20PermitWithSupply,
    AccessControl,
    IWrappedCoveredPrincipalToken
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // Address of the base/underlying token which is used to buy the yield bearing token from the wrapped position.
    // Ex - Dai is used to buy the yvDai yield bearing token
    address public immutable override baseToken;

    // Enumerable address list, It contains the list of allowed wrapped positions that are covered by this contract
    // Criteria to choose the wrapped position are -
    // a). Wrapped position should have same underlying/base token (i.e ETH, BTC, USDC).
    // b). Should have the similar risk profiles.
    EnumerableSet.AddressSet private _allowedWrappedPositions;

    // Tranche factory address for Tranche contract address derivation
    address internal immutable _trancheFactory;
    // Tranche bytecode hash for Tranche contract address derivation.
    // This is constant as long as Tranche does not implement non-constant constructor arguments.
    bytes32 internal immutable _trancheBytecodeHash;

    // Role identifier that can use to do some operational stuff.
    bytes32 public constant ADMIN_ROLE = bytes32("ADMIN_ROLE");

    // Role identifier that allow a particular account to reap principal tokens out of the contract.
    bytes32 public constant RECLAIM_ROLE = bytes32("RECLAIM_ROLE");

    // Emitted when new wrapped position get whitelisted.
    event WrappedPositionAdded(address _wrappedPosition);

    // Emitted when the principal tokens get reclaimed.
    event Reclaimed(address _tranche, uint256 _amount);

    /// @notice Modifier to validate the wrapped position is whitelisted or not.
    modifier isValidWp(address _wrappedPosition) {
        require(!isAllowedWp(_wrappedPosition), "WFP:ALREADY_EXISTS");
        _;
    }

    ///@notice Initialize the wrapped token.
    ///@dev    Wrapped token have 18 decimals, It is independent of the baseToken decimals.
    constructor(
        address _baseToken,
        address _owner,
        address __trancheFactory,
        bytes32 __trancheBytecodeHash
    )
        ERC20Permit(
            _processName(IERC20Metadata(_baseToken).symbol()),
            _processSymbol(IERC20Metadata(_baseToken).symbol())
        )
    {
        baseToken = _baseToken;
        _trancheFactory = __trancheFactory;
        _trancheBytecodeHash = __trancheBytecodeHash;
        _setupRole(ADMIN_ROLE, _owner);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(RECLAIM_ROLE, ADMIN_ROLE);
    }

    ///@notice Allows to create the name for the wrapped token.
    function _processName(string memory _tokenSymbol)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked("Wrapped", _tokenSymbol, "Covered Principal")
            );
    }

    ///@notice Allows to create the symbol for the wrapped token.
    function _processSymbol(string memory _tokenSymbol)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked("W", _tokenSymbol));
    }

    /// @notice Add wrapped position within the allowed wrapped position enumerable set.
    /// @dev    It is only allowed to execute by the owner of the contract.
    ///         wrapped position which has underlying token equals to the base token are
    ///         only allowed to add, Otherwise it will revert.
    /// @param  _wrappedPosition Address of the Wrapped position which needs to add.
    function addWrappedPosition(address _wrappedPosition)
        external
        override
        isValidWp(_wrappedPosition)
        onlyRole(ADMIN_ROLE)
    {
        require(
            address(IWrappedPosition(_wrappedPosition).token()) == baseToken,
            "WFP:INVALID_WP"
        );
        _allowedWrappedPositions.add(_wrappedPosition);
        emit WrappedPositionAdded(_wrappedPosition);
    }

    /// @notice Allows the defaulter to mint wrapped tokens (Covered position) by
    ///         sending the de-pegged token to the contract.
    /// @dev    a) Only allow minting the covered position when the derived tranche got expired otherwise revert.
    ///         b) Sufficient allowance of the principal token (i.e tranche) should be provided
    ///            to the contract by the `msg.sender` to make execution successful.
    /// @param  _amount Amount of covered position / wrapped token `msg.sender` wants to mint.
    /// @param  _expiration Timestamp at which the derived tranche would get expired.
    /// @param  _wrappedPosition Address of the Wrapped position which is used to derive the tranche.
    function mint(
        uint256 _amount,
        uint256 _expiration,
        address _wrappedPosition,
        PermitData calldata _permitCallData
    ) external override {
        require(isAllowedWp(_wrappedPosition), "WFP:INVALID_WP");
        address _tranche = address(
            _deriveTranche(_wrappedPosition, _expiration)
        );
        _usePermitData(_tranche, _permitCallData);
        // Only allow minting when the position get expired.
        require(_expiration < block.timestamp, "WFP:POSITION_NOT_EXPIRED");
        // Assumed that msg.sender provides the sufficient approval the contract.
        IERC20(_tranche).safeTransferFrom(
            msg.sender,
            address(this),
            _fromWad(_amount, _tranche)
        );
        // Mint the corresponding wrapped token to the `msg.sender`.
        _mint(msg.sender, _amount);
    }

    /// @notice Tell whether the given `_wrappedPosition` is whitelisted or not.
    /// @param  _wrappedPosition Address of the wrapped position.
    /// @return returns boolean, True -> allowed otherwise false.
    function isAllowedWp(address _wrappedPosition)
        public
        view
        override
        returns (bool)
    {
        return _allowedWrappedPositions.contains(_wrappedPosition);
    }

    /// @notice Returns the list of wrapped positions that are whitelisted with the contract.
    ///         Order is not maintained.
    /// @return Array of addresses.
    function allWrappedPositions()
        external
        view
        override
        returns (address[] memory)
    {
        return _allowedWrappedPositions.values();
    }

    /// @notice Reclaim tranche token (i.e principal token) by the authorized account.
    /// @dev    Only be called by the address which has the `RECLAIM_ROLE`, Should be Nexus Treasury.
    /// @param  _expiration Timestamp at which the derived tranche would get expired.
    /// @param  _wrappedPosition Address of the Wrapped position which is used to derive the tranche.
    /// @param  _to Address whom funds gets transferred.
    function reclaimPt(
        uint256 _expiration,
        address _wrappedPosition,
        address _to
    ) external override onlyRole(RECLAIM_ROLE) {
        require(isAllowedWp(_wrappedPosition), "WFP:INVALID_WP");
        address _tranche = address(
            _deriveTranche(_wrappedPosition, _expiration)
        );
        uint256 amount = IERC20(_tranche).balanceOf(address(this));
        IERC20(_tranche).safeTransfer(_to, amount);
        emit Reclaimed(_tranche, amount);
    }

    function _usePermitData(address _tranche, PermitData memory _d) internal {
        if (_d.spender != address(0)) {
            IERC20Permit(_tranche).permit(
                msg.sender,
                _d.spender,
                _d.value,
                _d.deadline,
                _d.v,
                _d.r,
                _d.s
            );
        }
    }

    /// @notice Converts the decimal precision of given `_amount` to `_tranche` decimal.
    function _fromWad(uint256 _amount, address _tranche)
        internal
        view
        returns (uint256)
    {
        return (_amount * 10**IERC20Metadata(_tranche).decimals()) / 1e18;
    }

    /// @dev This internal function produces the deterministic create2
    ///      address of the Tranche contract from a wrapped position contract and expiration
    /// @param _position The wrapped position contract address
    /// @param _expiration The expiration time of the tranche
    /// @return The derived Tranche contract
    function _deriveTranche(address _position, uint256 _expiration)
        internal
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
}
