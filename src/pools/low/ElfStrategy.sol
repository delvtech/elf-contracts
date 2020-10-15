pragma solidity >=0.5.8 <0.8.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/WETH.sol";

import "../../libraries/SafeMath.sol";
import "../../libraries/Address.sol";
import "../../libraries/SafeERC20.sol";

import "../../assets/YearnDaiVault.sol";
import "../../assets/YearnUsdcVault.sol";
import "../../assets/YearnTusdVault.sol";

import "../../converter/interface/IElementConverter.sol";
import "../../assets/interface/IElementAsset.sol";
import "../../oracles/interface/IElementPriceOracle.sol";

contract ElfStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 weth;

    struct Allocation {
        address fromToken;
        address toToken;
        uint256 percent;
        address asset;
        uint256 converterType; // aave,compound,balancer,uniswap
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
        uint256[] memory _percents,
        address[] memory _asset,
        uint256[] memory _converterType,
        uint256 _numAllocations
    ) public {
        require(msg.sender == governance, "!governance");
        // todo: validate that allocations add to 100
        delete allocations;
        for (uint256 i = 0; i < _numAllocations; i++) {
            allocations.push(
                Allocation(
                    _fromToken[i],
                    _toToken[i],
                    _percents[i],
                    _asset[i],
                    _converterType[i]
                )
            );
        }
        numAllocations = _numAllocations;
    }

    function allocate(uint256 _amount) public {
        require(msg.sender == pool, "!pool ");
        weth.safeTransfer(converter, _amount);
        for (uint256 i = 0; i < numAllocations; i++) {
            uint256 _fromTokenAmount = _amount.mul(allocations[i].percent).div(
                100
            );
            // convert weth to asset base type (e.g. dai)
            IElementConverter(converter).convert(
                allocations[i].fromToken,
                allocations[i].toToken,
                _fromTokenAmount,
                allocations[i].converterType,
                true,
                address(this)
            );
            uint256 _toTokenAmount = IERC20(allocations[i].toToken).balanceOf(
                address(this)
            );
            // deposit into investment asset
            IERC20(allocations[i].toToken).safeTransfer(
                allocations[i].asset,
                _toTokenAmount
            );
            IElementAsset(allocations[i].asset).deposit(_toTokenAmount);
        }
    }

    function deallocate(uint256 _amount) public {
        require(msg.sender == pool, "!pool ");

        for (uint256 i = 0; i < numAllocations; i++) {
            uint256 totalAssetAmount = IElementAsset(allocations[i].asset)
                .balanceOf();

            // calculate the % of total being withdrawn and withdraw that % from each asset
            uint256 _assetWithdrawAmount = totalAssetAmount.mul(_amount).div(
                balanceOf()
            );

            // withdraw from asset
            IElementAsset(allocations[i].asset).withdraw(
                _assetWithdrawAmount,
                address(this)
            );

            IERC20(allocations[i].toToken).safeTransfer(
                converter,
                _assetWithdrawAmount
            );

            // convert base asset to weth
            IElementConverter(converter).convert(
                allocations[i].toToken,
                allocations[i].fromToken,
                _assetWithdrawAmount,
                allocations[i].converterType,
                false,
                address(this)
            );
        }
    }

    // withdraw a certain amount
    function withdraw(uint256 _amount) public {
        require(msg.sender == pool, "!pool ");
        weth.safeTransfer(msg.sender, _amount);
    }

    // possibly a withdrawAll() function

    function balanceOf() public view returns (uint256) {
        uint256 assetBalance = 0;
        for (uint256 i = 0; i < numAllocations; i++) {
            assetBalance = assetBalance.add(
                IElementAsset(allocations[i].asset).balanceOf().div(
                    _getPrice(allocations[i].asset)
                )
            );
        }
        return weth.balanceOf(address(this)).add(assetBalance);
    }

    function _getPrice(address _token) internal view returns (uint256 p) {
        return IElementPriceOracle(priceOracle).getPrice(_token, address(weth));
    }

    receive() external payable {}
}
