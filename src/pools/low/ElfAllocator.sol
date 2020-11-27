// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/WETH.sol";
import "../../interfaces/IBPool.sol";

import "../../libraries/SafeMath.sol";
import "../../libraries/Address.sol";
import "../../libraries/SafeERC20.sol";

import "../../lenders/interface/IElfLender.sol";
import "../../assets/interface/IElfAsset.sol";
import "../../oracles/interface/IElfPriceOracle.sol";

contract ElfAllocator {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 private _weth;

    struct Allocation {
        address fromToken;
        address toToken;
        address lender;
        uint256 percent;
        address asset;
    }

    Allocation[] public allocations;
    uint256 public numAllocations;

    address public governance;
    address public pool;
    address public priceOracle;

    /**
     * @dev modifier to only allow the governance contract to call the function.
     */
    modifier onlyGovernance {
        require(msg.sender == governance, "Caller is not governance contract");
        _;
    }

    /**
     * @dev modifier to only allow the pool contract to call the function.
     */
    modifier onlyPool {
        require(msg.sender == pool, "Caller is not the pool contract");
        _;
    }

    constructor(address _pool, address payable weth) public {
        governance = msg.sender;
        pool = _pool;
        _weth = IERC20(weth);
    }

    function setGovernance(address _governance) public onlyGovernance {
        governance = _governance;
    }

    function setPool(address _pool) public onlyGovernance {
        pool = _pool;
    }

    function setPriceOracle(address _priceOracle) public onlyGovernance {
        priceOracle = _priceOracle;
    }

    function setAllocations(
        address[] memory _fromToken,
        address[] memory _toToken,
        address[] memory _lenders,
        uint256[] memory _percents,
        address[] memory _asset,
        uint256 _numAllocations
    ) public onlyGovernance {
        uint256 _totalAllocations;

        delete allocations;

        for (uint256 i = 0; i < _numAllocations; i++) {
            allocations.push(
                Allocation(
                    _fromToken[i],
                    _toToken[i],
                    _lenders[i],
                    _percents[i],
                    _asset[i]
                )
            );
            _totalAllocations = _totalAllocations.add(_percents[i]);
        }

        require(_totalAllocations == 100, "!100");

        numAllocations = _numAllocations;
    }

    function getNumAllocations() external view returns (uint256) {
        return numAllocations;
    }

    function getAllocations()
        external
        view
        returns (
            address[] memory,
            address[] memory,
            address[] memory,
            uint256[] memory,
            address[] memory,
            uint256
        )
    {
        address[] memory fromTokens = new address[](numAllocations);
        address[] memory toTokens = new address[](numAllocations);
        address[] memory lenders = new address[](numAllocations);
        uint256[] memory percents = new uint256[](numAllocations);
        address[] memory assets = new address[](numAllocations);
        for (uint256 i = 0; i < numAllocations; i++) {
            fromTokens[i] = allocations[i].fromToken;
            toTokens[i] = allocations[i].toToken;
            lenders[i] = allocations[i].lender;
            percents[i] = allocations[i].percent;
            assets[i] = allocations[i].asset;
        }
        return (
            fromTokens,
            toTokens,
            lenders,
            percents,
            assets,
            numAllocations
        );
    }

    function allocate(uint256 _amount) public onlyPool {
        for (uint256 i = 0; i < numAllocations; i++) {
            uint256 _fromTokenAmount = _amount.mul(allocations[i].percent).div(
                100
            );

            IERC20(allocations[i].fromToken).safeTransfer(
                allocations[i].lender,
                _fromTokenAmount
            );
            IElfLender(allocations[i].lender).depositAndBorrow(
                _fromTokenAmount
            );

            uint256 borrowed = IERC20(allocations[i].toToken).balanceOf(
                address(this)
            );

            IERC20(allocations[i].toToken).safeTransfer(
                allocations[i].asset,
                borrowed
            );

            IElfAsset(allocations[i].asset).deposit(borrowed);
        }
    }

    function deallocate(uint256 _amount) public onlyPool {
        for (uint256 i = 0; i < numAllocations; i++) {
            address vault = IElfAsset(allocations[i].asset).vault();
            uint256 totalAssetAmount = IERC20(vault).balanceOf(address(this));

            uint256 _assetWithdrawAmount = totalAssetAmount.mul(_amount).div(
                balance()
            );

            IERC20(vault).safeTransfer(
                allocations[i].asset,
                _assetWithdrawAmount
            );

            IElfAsset(allocations[i].asset).withdraw(
                _assetWithdrawAmount,
                address(this)
            );

            uint256 balance = IERC20(allocations[i].toToken).balanceOf(
                address(this)
            );

            IERC20(allocations[i].toToken).safeTransfer(
                allocations[i].lender,
                balance
            );

            IElfLender(allocations[i].lender).repayAndWithdraw(balance);
        }
    }

    // withdraw a certain amount
    function withdraw(uint256 _amount) public onlyPool {
        _weth.safeTransfer(msg.sender, _amount);
    }

    function balance() public view returns (uint256) {
        uint256 balances;
        for (uint256 i = 0; i < numAllocations; i++) {
            balances = balances.add(
                IElfLender(allocations[i].lender).balances()
            );
        }
        return _weth.balanceOf(address(this)).add(balances);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
