pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

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

    function getAddress() external view returns (address) {
        return yVaultUsdc;
    }

    function deposit(uint256 _amount, address _sender) external {
        IERC20(usdc).safeTransfer(msg.sender, _amount);
        YearnVault(yVaultUsdc).deposit(_amount);
    }

    function withdraw(uint256 _amount, address _sender) external {
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
