pragma solidity ^0.8.0;

import "../libraries/ERC20.sol";
import "../libraries/ERC20Permit.sol";
import "../libraries/DateString.sol";

import "../interfaces/IYC.sol";

contract YC is ERC20Permit, IYC {
    // The tranche address which controls the minting
    address public immutable tranche;

    /// @dev Initializes the ERC20 and writes the correct names
    /// @param _tranche The tranche contract address
    /// @param strategySymbol The symbol of the associated ELF contract
    /// @param timestamp The unlock time on the tranche
    constructor(
        address _tranche,
        string memory strategySymbol,
        uint256 timestamp,
        uint8 _decimals
    ) ERC20("Yield Coupon ", "YC:") ERC20Permit("Yield Coupon") {
        tranche = _tranche;
        _setupDecimals(_decimals);
        // Write the elfSymbol and expiration time to name and symbol
        DateString.encodeAndWriteTimestamp(strategySymbol, timestamp, _name);
        DateString.encodeAndWriteTimestamp(strategySymbol, timestamp, _symbol);
    }

    /// @dev Prevents execution if the caller isn't the tranche
    modifier onlyMintAuthority() {
        require(msg.sender == tranche, "caller is not an authorized minter");
        _;
    }

    /// @dev Mints tokens to an address
    /// @param _account The account to mint too
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
