pragma solidity 0.6.7;

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";

import "../oracles/interface/IElementPriceOracle.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract ASPV {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 weth;
    IERC20 borrowAsset;

    uint256 public balances;
    uint256 public liabilities;

    address public allocator;
    address public governance;
    address public priceOracle;

    constructor(
        address _weth,
        address _borrowAsset,
        address _allocator // address _governance
    ) public {
        weth = IERC20(_weth);
        borrowAsset = IERC20(_borrowAsset);
        allocator = _allocator;
        // governance  = _governance;
    }

    function setGovernance(address _governance) public {
        // require(msg.sender == governance, "SPV/not-governance");
        governance = _governance;
    }

    function setPriceOracle(address _priceOracle) public {
        // require(msg.sender == governance, "SPV/not-goverance");
        priceOracle = _priceOracle;
    }

    function depositAndBorrow(uint256 _amount) external {
        require(msg.sender == allocator, "aspv/not-allocator");
        balances = balances.add(_amount);
        liabilities = liabilities.add(_amount);

        borrowAsset.transfer(msg.sender, _amount);
    }

    function repayAndWithdraw(uint256 _amount) external {
        require(msg.sender == allocator);
        balances = balances.sub(_amount);
        liabilities = liabilities.sub(_amount);

        uint256 bal = weth.balanceOf(address(this));
        weth.transfer(msg.sender, _amount);
    }

    function getLendingPrice(address _fromToken, address _toToken)
        public
        view
        returns (uint256)
    {
        return IElementPriceOracle(priceOracle).getPrice(_fromToken, _toToken);
    }

    function balance() public view returns (uint256) {
        return weth.balanceOf(address(this));
    }
}