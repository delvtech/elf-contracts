// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

import { IERC20Permit } from "../../../interfaces/IERC20Permit.sol";

interface IWrappedFuturesPrincipal is IERC20Permit {
    // Address of the base/underlying token which is used to buy the yield bearing token from the wrapped position.
    // Ex - LUSD is used to buy the Curve LUSD v2 yield bearing token
    function baseToken() external view returns (address);

    /// @notice Add tranches within the allowed tranches enumerable set.
    /// @dev    It is only allowed to execute by the owner of the contract.
    ///         Tranches which has underlying token equals to the base token are
    ///         only allowed to add, Otherwise it will revert.
    /// @param  _tranche Address of the tranche which needs to add.
    function addTranche(address _tranche) external;

    /// @notice Allows the defaulter to mint wrapped tokens (Covered position) by
    ///         sending the de-pegged token to the contract.
    /// @dev    a) Only allow minting the covered position when the tranche got expired otherwise revert.
    ///         b) Sufficient allowance of the principal token (i.e tranche) should be provided
    ///            to the contract by the `msg.sender` to make execution successful.
    /// @param  _amount Amount of covered position / wrapped token `msg.sender` wants to mint.
    /// @param  _tranche Address of the tranche which is covered by this covered position contract / wrapped token.
    function mint(uint256 _amount, address _tranche) external;

    /// @notice Tell whether the given `_tranche` is whitelisted or not.
    /// @param  _tranche Address of the tranche.
    /// @return returns boolean, True -> allowed otherwise false.
    function isAllowedTranche(address _tranche) external view returns (bool);

    /// @notice Returns the list of tranches that are whitelisted with the contract.
    ///         Order is not maintained.
    /// @return Array of addresses.
    function allTranches() external view returns (address[] memory);

    /// @notice Returns price of the de-pegged token i.e principal token in terms of base asset.
    /// @param  _tranche Address of the tranche, corresponds to which price get queried.
    /// @return uint256 Price of de-pegged token in terms of base asset.
    function getPrice(address _tranche) external view returns (uint256);
}
