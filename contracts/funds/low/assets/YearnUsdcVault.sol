pragma solidity >=0.5.8 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../../interfaces/YearnVault.sol";

contract YearnUsdcVault {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant weth = address(
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    );
    address public constant usdc = address(
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    );
    address public constant yVaultUsdc = address(
        0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e
    );

    address public governance;
    address public strategy;

    constructor(address _strategy) public {
        governance = msg.sender;
        strategy = _strategy;
        _approve();
    }

    function deposit() external {
        YearnVault(yVaultUsdc).depositAll();
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == strategy, "!strategy");
        uint256 _shares = _amount.mul(1e18).div(
            YearnVault(yVaultUsdc).getPricePerFullShare()
        );

        if (_shares > IERC20(yVaultUsdc).balanceOf(address(this))) {
            _shares = IERC20(yVaultUsdc).balanceOf(address(this));
        }
        YearnVault(yVaultUsdc).withdraw(_shares);
    }

    function balanceOf() public view returns (uint256) {
        // TODO
        return 0;
    }

    function _getPrice() internal view returns (uint256 p) {
        // TODO: price oracle
        return 1;
    }

    function _approve() internal {
        // TODO
    }
}
