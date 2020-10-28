pragma solidity 0.6.7;

import "./interfaces/IElePool.sol";

contract EleProxy {

    function deposit(address _pool, uint256 _amount) external {
        (bool success, ) = _pool.delegatecall(
            abi.encodeWithSignature("deposit(uint256)", _amount)
        );
    }

    function depositETH(address _pool) external {
        (bool success, ) = _pool.delegatecall(
            abi.encodeWithSignature("depositETH()")
        );
    }

    function withdraw(address _pool, uint256 _shares) external {
        (bool success, ) = _pool.delegatecall(
            abi.encodeWithSignature("withdraw(uint256)", _shares)
        );
    }

    function withdrawETH(address _pool, uint256 _shares) external {
        (bool success, ) = _pool.delegatecall(
            abi.encodeWithSignature("withdraw(uint256)", _shares)
        );
    }

    function getWalletBalance(address _pool) external returns (uint256) {
        return IERC20(_pool).balanceOf(msg.sender);
    }

    function getPoolBalance(address _pool) external returns (uint256) {
        return 1337 * 10 ** 18;
    }

    function getLender() // loop through an array

    function getPoolAPY(address _pool) external returns (uint256) {

        return 125 * 10 ** 18;
    }

    // function getpoolAssetsAndAllocations(address _pool) external returns ()

}
