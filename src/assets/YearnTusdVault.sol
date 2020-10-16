pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

contract YearnTUsdVault {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* solhint-disable const-name-snakecase */
    address public constant weth = address(
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    );
    address public constant token = address(
        0xdAC17F958D2ee523a2206206994597C13D831ec7
    );
    address public constant yVaultTusd = address(
        0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a
    );
    /* solhint-enable const-name-snakecase */

    address public governance;
    address public strategy;

    constructor(address _strategy) public {
        governance = msg.sender;
        strategy = _strategy;
    }

    function getAddress() external view returns (address) {
        return yVaultTusd;
    }

    function deposit(uint256 _amount) external {
        require(msg.sender == strategy, "!strategy");
        YearnVault(yVaultTusd).deposit(_amount);
    }

    function withdraw(uint256 _amount, address _sender) external {
        require(msg.sender == strategy, "!strategy");
        uint256 _shares = _amount.mul(1e18).div(
            YearnVault(yVaultTusd).getPricePerFullShare()
        );

        if (_shares > IERC20(yVaultTusd).balanceOf(address(this))) {
            _shares = IERC20(yVaultTusd).balanceOf(address(this));
        }
        YearnVault(yVaultTusd).withdraw(_shares);
        IERC20(token).safeTransfer(_sender, _amount);
    }

    function balanceOf() public view returns (uint256) {
        // TODO
        return 0;
    }

    function _getPrice() internal view returns (uint256 p) {
        // TODO: price oracle
        return 1;
    }
}
