pragma solidity >=0.5.8 <0.8.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/WETH.sol";
import "../../interfaces/IBPool.sol";
import "../../interfaces/ISPV.sol";

import "../../libraries/SafeMath.sol";
import "../../libraries/Address.sol";
import "../../libraries/SafeERC20.sol";

import "../../assets/interface/IElementAsset.sol";
import "../../oracles/interface/IElementPriceOracle.sol";

contract ElfAllocator {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 private weth;

    struct Allocation {
        address fromToken;
        address toToken;
        address vehicle;
        uint256 percent;
        address asset;
    }

    Allocation[] public allocations;
    uint256 public numAllocations;

    address public governance;
    address public pool;
    address public converter;
    address public priceOracle;

    address public constant ETH = address(
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    );

    constructor(address _pool, address payable _weth) public {
        governance = msg.sender;
        pool = _pool;
        weth = IERC20(_weth);
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setConverter(address _converter) public {
        require(msg.sender == governance, "!governance");
        converter = _converter;
    }

    function setPriceOracle(address _priceOracle) public {
        require(msg.sender == governance, "!governance");
        priceOracle = _priceOracle;
    }

    function setAllocations(
        address[] memory _fromToken,
        address[] memory _toToken,
        address[] memory _vehicles,
        uint256[] memory _percents,
        address[] memory _asset,
        uint256 _numAllocations
    ) public {
        require(msg.sender == governance, "!governance");
        uint256 _totalAllocations;
        delete allocations;
        for (uint256 i = 0; i < _numAllocations; i++) {
            allocations.push(
                Allocation(
                    _fromToken[i],
                    _toToken[i],
                    _vehicles[i],
                    _percents[i],
                    _asset[i]
                )
            );
            _totalAllocations = _totalAllocations.add(_percents[i]);
        }
        require(_totalAllocations == 100, "!100");
        numAllocations = _numAllocations;
    }

    function allocate(uint256 _amount) public {
        require(msg.sender == pool, "allocator/must-be-pool");

        for (uint256 i = 0; i < numAllocations; i++) {
            uint256 _fromTokenAmount = _amount.mul(allocations[i].percent).div(
                100
            );

            IERC20(allocations[i].fromToken).safeTransfer(
                allocations[i].vehicle,
                _fromTokenAmount
            );
            ISPV(allocations[i].vehicle).depositAndBorrow(_fromTokenAmount);

            uint256 borrowed = IERC20(allocations[i].toToken).balanceOf(
                address(this)
            );

            IERC20(allocations[i].toToken).safeTransfer(
                allocations[i].asset,
                borrowed
            );

            IElementAsset(allocations[i].asset).deposit(borrowed);
        }
    }

    function deallocate(uint256 _amount) public {
        require(msg.sender == pool, "!pool ");

        for (uint256 i = 0; i < numAllocations; i++) {
            address vault = IElementAsset(allocations[i].asset).vault();
            uint256 totalAssetAmount = IERC20(vault).balanceOf(address(this));

            uint256 _assetWithdrawAmount = totalAssetAmount.mul(_amount).div(
                balance()
            );

            IERC20(vault).safeTransfer(
                allocations[i].asset,
                _assetWithdrawAmount
            );

            IElementAsset(allocations[i].asset).withdraw(
                _assetWithdrawAmount,
                address(this)
            );

            uint256 balance = IERC20(allocations[i].toToken).balanceOf(
                address(this)
            );

            IERC20(allocations[i].toToken).safeTransfer(
                allocations[i].vehicle,
                balance
            );

            ISPV(allocations[i].vehicle).repayAndWithdraw(balance);
        }
    }

    // withdraw a certain amount
    function withdraw(uint256 _amount) public {
        require(msg.sender == pool, "!pool ");
        weth.safeTransfer(msg.sender, _amount);
    }

    // possibly a withdrawAll() function

    function balance() public view returns (uint256) {
        uint256 balances;
        for (uint256 i = 0; i < numAllocations; i++) {
            balances = balances.add(ISPV(allocations[i].vehicle).balances());
        }
        return weth.balanceOf(address(this)).add(balances);
    }

    function _getPrice(address _token) internal view returns (uint256 p) {
        return IElementPriceOracle(priceOracle).getPrice(_token, address(weth));
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
