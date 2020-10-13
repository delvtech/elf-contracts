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
        uint256 conversionType; // 0 = loan, 1 = withdraw, 2 = swap
        uint256 implementation; // 0 = aave,balancer, 1 = compound,uniswap
    }

    Allocation[] public allocations;
    uint256 public numAllocations;

    address public governance;
    address public fund;
    address public converter;

    address public constant ETH = address(
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    );

    constructor(address _fund, address payable _weth) public {
        governance = msg.sender;
        fund = _fund;
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

    function setAllocations(
        address[] memory _fromToken,
        address[] memory _toToken,
        uint256[] memory _percents,
        address[] memory _asset,
        uint256[] memory _conversionType,
        uint256[] memory _implementation,
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
                    _conversionType[i],
                    _implementation[i]
                )
            );
        }
        numAllocations = _numAllocations;
    }

    function allocate(uint256 _amount) public {
        require(msg.sender == fund, "!fund");
        weth.safeTransfer(converter, _amount);
        for (uint256 i = 0; i < numAllocations; i++) {
            uint256 _assetAmount = _amount.mul(allocations[i].percent).div(100);
            // convert weth to asset base type (e.g. dai)
            IElementConverter(converter).convert(
                allocations[i].fromToken,
                allocations[i].toToken,
                _assetAmount,
                allocations[i].conversionType,
                allocations[i].implementation,
                address(this)
            );
            // deposit into investment asset
            // TODO:  this is dumb.
            IERC20(allocations[i].toToken).safeTransfer(
                allocations[i].asset,
                _assetAmount
            );
            // TODO: this assumes a 1 to 1 trade of fromToken to toToken
            IElementAsset(allocations[i].asset).deposit(_assetAmount);
        }
    }

    function deallocate(uint256 _amount) public {
        require(msg.sender == fund, "!fund");

        for (uint256 i = 0; i < numAllocations; i++) {
            uint256 _assetAmount = _amount.mul(allocations[i].percent).div(100);
            // withdraw from asset
            // TODO: this assumes a 1 to 1 trade of fromToken to toToken
            IElementAsset(allocations[i].asset).withdraw(
                _assetAmount,
                address(this)
            );
            // TODO:  this is dumb.
            IERC20(allocations[i].toToken).safeTransfer(
                converter,
                _assetAmount
            );
            // convert base asset to weth
            IElementConverter(converter).convert(
                allocations[i].toToken,
                allocations[i].fromToken,
                _assetAmount,
                1, //TODO: this tells the converter to withdraw.  need a better way to do this
                allocations[i].implementation,
                address(this)
            );
        }
    }

    // withdraw a certain amount
    function withdraw(uint256 _amount) public {
        require(msg.sender == fund, "!fund");
        weth.safeTransfer(msg.sender, _amount);
    }

    // possibly a withdrawAll() function

    function balanceOf() public view returns (uint256) {
        return
            weth.balanceOf(address(this)).add(
                IElementConverter(converter).balanceOf()
            );
    }

    receive() external payable {}
}
