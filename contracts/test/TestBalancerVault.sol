// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IVault.sol";
import "./TestERC20.sol";

contract TestBalancerVault is IVault {
    struct TwoTokens {
        TestERC20 token1;
        TestERC20 token2;
    }

    struct TwoNumbers {
        uint256 balance1;
        uint256 balance2;
    }

    mapping(bytes32 => TestERC20) public lpTokens;
    mapping(bytes32 => TwoTokens) public componentTokens;
    mapping(bytes32 => TwoNumbers) public balances;
    uint256 poolCount = 0;

    function makePool(address token1, address token2)
        external
        returns (bytes32 poolID)
    {
        TestERC20 lpToken = new TestERC20("test", "test", 18);
        poolCount++;
        lpTokens[bytes32(poolCount)] = lpToken;
        componentTokens[bytes32(poolCount)] = TwoTokens(
            TestERC20(token1),
            TestERC20(token2)
        );
        return bytes32(poolCount);
    }

    function getPool(bytes32 poolId)
        external
        view
        override
        returns (address, PoolSpecialization)
    {
        return (address(lpTokens[poolId]), PoolSpecialization.TWO_TOKEN);
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable override {
        require(
            request.maxAmountsIn[0] == request.maxAmountsIn[1],
            "Wrong ratio"
        );
        TestERC20 lp = lpTokens[poolId];
        uint256 totalSupply = lp.totalSupply();
        TwoNumbers memory balance = balances[poolId];

        uint256 newShares = totalSupply == 0
            ? request.maxAmountsIn[0]
            : (totalSupply * request.maxAmountsIn[0]) / balance.balance1;

        TwoTokens memory tokens = componentTokens[poolId];

        tokens.token1.transferFrom(
            sender,
            address(this),
            request.maxAmountsIn[0]
        );
        tokens.token2.transferFrom(
            sender,
            address(this),
            request.maxAmountsIn[1]
        );

        balance.balance1 += request.maxAmountsIn[0];
        balance.balance2 += request.maxAmountsIn[1];
        balances[poolId] = balance;

        lp.mint(recipient, newShares);
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external override {
        require(
            request.minAmountsOut[0] == request.minAmountsOut[1],
            "Wrong ratio"
        );
        TestERC20 lp = lpTokens[poolId];
        uint256 totalSupply = lp.totalSupply();
        TwoNumbers memory balance = balances[poolId];

        uint256 sharesNeeded = (totalSupply * request.minAmountsOut[0]) /
            balance.balance1;
        lp.burn(sender, sharesNeeded);

        TwoTokens memory tokens = componentTokens[poolId];

        tokens.token1.transfer(recipient, request.minAmountsOut[0]);
        tokens.token2.transfer(recipient, request.minAmountsOut[1]);

        balance.balance1 -= request.minAmountsOut[0];
        balance.balance2 -= request.minAmountsOut[1];
        balances[poolId] = balance;
    }
}
