// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.7.0;

import "../balancer-core-v2/pools/factories/BasePoolFactory.sol";
import "../libraries/Authorizable.sol";
import "../ConvergentCurvePool.sol";

/// @author Element Finance
/// @title Convergent Pool Factory
contract ConvergentPoolFactory is BasePoolFactory, Authorizable {
    // This contract deploys convergent pools

    // The 18 point encoded percent fee paid to governance by the pool
    // Defaults to 0 and must be enabled by governance
    uint256 public percentFeeGov;
    address public governance;

    /// @notice This event tracks pool creations from this factory
    /// @param pool the address of the pool
    /// @param bondToken The token of the bond token in this pool
    event CCPoolCreated(address indexed pool, address indexed bondToken);

    /// @notice This function constructs the pool
    /// @param _vault The balancer v2 vault
    /// @param _governance The governance address
    constructor(IVault _vault, address _governance)
        BasePoolFactory(_vault)
        Authorizable()
    {
        // Sets the governance address as owner and authorized
        _authorize(_governance);
        setOwner(_governance);
        governance = _governance;
    }

    /// @notice Deploys a new `ConvergentPool`.
    /// @param _underlying The asset which is converged to ie 'base'
    /// @param _bond The asset which converges to the underlying
    /// @param _expiration The time at which convergence finishes
    /// @param _unitSeconds The unit seconds multiplier for time
    /// @param _percentFee The fee percent of each trades implied yield paid to gov.
    /// @param _name The name of the balancer v2 lp token for this pool
    /// @param _symbol The symbol of the balancer v2 lp token for this pool
    /// @param _pauser An address with the power to stop trading and deposits
    /// @return The new pool address
    function create(
        address _underlying,
        address _bond,
        uint256 _expiration,
        uint256 _unitSeconds,
        uint256 _percentFee,
        string memory _name,
        string memory _symbol,
        address _pauser
    ) external returns (address) {
        address pool = address(
            new ConvergentCurvePool(
                IERC20(_underlying),
                IERC20(_bond),
                _expiration,
                _unitSeconds,
                getVault(),
                _percentFee,
                percentFeeGov,
                governance,
                _name,
                _symbol,
                _pauser
            )
        );
        // Register the pool with the vault
        _register(pool);
        // Emit a creation event
        emit CCPoolCreated(pool, _bond);
        return pool;
    }

    /// @notice Allows governance to set the new percent fee for governance
    /// @param newFee The new percentage fee
    function setGovFee(uint256 newFee) external onlyAuthorized {
        require(newFee < 3e17, "New fee higher than 30%");
        percentFeeGov = newFee;
    }

    /// @notice Allows the owner to change the governance minting address
    /// @param newGov The new address to receive rewards in pools
    function setGov(address newGov) external onlyOwner {
        governance = newGov;
    }
}
