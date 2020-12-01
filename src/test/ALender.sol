// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";

import "../oracles/interface/IElfPriceOracle.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract ALender {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public weth;
    IERC20 public borrowAsset;

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
        // require(msg.sender == governance, "Lender/not-governance");
        governance = _governance;
    }

    function setPriceOracle(address _priceOracle) public {
        // require(msg.sender == governance, "Lender/not-goverance");
        priceOracle = _priceOracle;
    }

    function depositAndBorrow(uint256 _amount) external {
        require(msg.sender == allocator, "aLender/not-allocator");
        balances = balances.add(_amount);
        liabilities = liabilities.add(_amount);

        borrowAsset.transfer(msg.sender, _amount);
    }

    function repayAndWithdraw(uint256 _amount) external {
        require(msg.sender == allocator);
        balances = balances.sub(_amount);
        liabilities = liabilities.sub(_amount);

        weth.transfer(msg.sender, _amount);
    }

    function getLendingPrice(address _fromToken, address _toToken)
        public
        view
        returns (uint256)
    {
        return IElfPriceOracle(priceOracle).getPrice(_fromToken, _toToken);
    }

    function balance() public view returns (uint256) {
        return weth.balanceOf(address(this));
    }
}
