// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./libraries/ERC20Permit.sol";
import "./libraries/DateString.sol";

import "./interfaces/IInterestToken.sol";
import "./interfaces/ITranche.sol";

contract InterestToken is ERC20Permit, IInterestToken {
    // The tranche address which controls the minting
    ITranche public immutable tranche;

    /// @dev Initializes the ERC20 and writes the correct names
    /// @param _tranche The tranche contract address
    /// @param _strategySymbol The symbol of the associated WrappedPosition contract
    /// @param _timestamp The unlock time on the tranche
    constructor(
        address _tranche,
        string memory _strategySymbol,
        uint256 _timestamp,
        uint8 _decimals
    ) ERC20Permit("Element Yield Token ", "eY:") {
        tranche = ITranche(_tranche);
        _setupDecimals(_decimals);
        // Write the strategySymbol and expiration time to name and symbol
        DateString.encodeAndWriteTimestamp(_strategySymbol, _timestamp, name);
        DateString.encodeAndWriteTimestamp(_strategySymbol, _timestamp, symbol);
    }

    /// @dev Aliasing of the lookup method for the supply of yield tokens which
    ///      improves our ERC20 compatibility.
    /// @return The total supply of yield tokens
    function totalSupply() external view returns (uint256) {
        return uint256(tranche.interestSupply());
    }

    /// @dev Prevents execution if the caller isn't the tranche
    modifier onlyMintAuthority() {
        require(
            msg.sender == address(tranche),
            "caller is not an authorized minter"
        );
        _;
    }

    /// @dev Mints tokens to an address
    /// @param _account The account to mint to
    /// @param _amount The amount to mint
    function mint(address _account, uint256 _amount)
        external
        override
        onlyMintAuthority
    {
        _mint(_account, _amount);
    }

    /// @dev Burns tokens from an address
    /// @param _account The account to burn from
    /// @param _amount The amount of token to burn
    function burn(address _account, uint256 _amount)
        external
        override
        onlyMintAuthority
    {
        _burn(_account, _amount);
    }
}
