pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract YearnDaiVault {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* solhint-disable const-name-snakecase */
    address public constant weth = address(
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    );
    address public constant token = address(
        0x6B175474E89094C44Da98b954EedeAC495271d0F
    );
    address public constant yVaultDAI = address(
        0xACd43E627e64355f1861cEC6d3a6688B31a6F952
    );
    /* solhint-enable const-name-snakecase */

    address public governance;
    address public strategy;

    constructor(address _strategy) public {
        governance = msg.sender;
        strategy = _strategy;
    }

    function getAddress() external view returns (address) {
        return yVaultDAI;
    }

    function deposit(uint256 _amount) external {
        require(msg.sender == strategy, "!strategy");
        // approve yVaultDAI use DAI
        YearnVault(yVaultDAI).deposit(_amount);
    }

    function withdraw(uint256 _amount, address _sender) external {
        require(msg.sender == strategy, "!strategy");
        uint256 _shares = _amount.mul(1e18).div(
            YearnVault(yVaultDAI).getPricePerFullShare()
        );

        if (_shares > IERC20(yVaultDAI).balanceOf(address(this))) {
            _shares = IERC20(yVaultDAI).balanceOf(address(this));
        }
        YearnVault(yVaultDAI).withdraw(_shares);
        IERC20(token).safeTransfer(_sender, _amount);
    }

    function balanceOf() public view returns (uint256) {
        // TODO
        return 0;
    }

    function _getPrice() internal view returns (uint256 p) {
        // TODO: price oracle
        return 0;
    }
}
