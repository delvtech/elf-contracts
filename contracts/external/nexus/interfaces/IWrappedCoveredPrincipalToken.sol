// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

import { IERC20Permit } from "../../../interfaces/IERC20Permit.sol";

interface IWrappedCoveredPrincipalToken is IERC20Permit {
    // Memory encoding of the permit data
    struct PermitData {
        address spender;
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // Address of the base/underlying token which is used to buy the yield bearing token from the wrapped position.
    // Ex - Dai is used to buy the yvDai yield bearing token.
    function baseToken() external view returns (address);

    /// @notice Add wrapped position within the allowed wrapped position enumerable set.
    /// @dev    It is only allowed to execute by the owner of the contract.
    ///         wrapped position which has underlying token equals to the base token are
    ///         only allowed to add, Otherwise it will revert.
    /// @param  _wrappedPosition Address of the Wrapped position which needs to add.
    function addWrappedPosition(address _wrappedPosition) external;

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
    ) external;

    /// @notice Tell whether the given `_wrappedPosition` is whitelisted or not.
    /// @param  _wrappedPosition Address of the wrapped position.
    /// @return returns boolean, True -> allowed otherwise false.
    function isAllowedWp(address _wrappedPosition) external view returns (bool);

    /// @notice Returns the list of wrapped positions that are whitelisted with the contract.
    ///         Order is not maintained.
    /// @return Array of addresses.
    function allWrappedPositions() external view returns (address[] memory);

    /// @notice Reclaim tranche token (i.e principal token) by the authorized account.
    /// @dev    Only be called by the address which has the `RECLAIM_ROLE`, Should be Nexus Treasury.
    /// @param  _expiration Timestamp at which the derived tranche would get expired.
    /// @param  _wrappedPosition Address of the Wrapped position which is used to derive the tranche.
    /// @param  _to Address whom funds gets transferred.
    function reclaimPt(
        uint256 _expiration,
        address _wrappedPosition,
        address _to
    ) external;
}
