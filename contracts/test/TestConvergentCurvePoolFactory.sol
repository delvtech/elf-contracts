// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.7.0;

import "./TestConvergentCurvePool.sol";
import "../interfaces/IERC20Decimals.sol";
import "../balancer-core-v2/vault/interfaces/IVault.sol";

contract TestConvergentCurvePoolFactory {
    uint256 public oraclePeriod;

    event CCPoolCreated(address pool);

    constructor() {
        oraclePeriod = 30 minutes;
    }

    function create(
        IERC20 _underlying,
        IERC20 _bond,
        uint256 _expiration,
        uint256 _unitSeconds,
        IVault vault,
        uint256 _percentFee,
        address _governance,
        string memory name,
        string memory symbol
    ) external {
        address pool = address(
            new TestConvergentCurvePool(
                _underlying,
                _bond,
                _expiration,
                _unitSeconds,
                vault,
                _percentFee,
                _governance,
                name,
                symbol
            )
        );
        emit CCPoolCreated(pool);
    }
}
