pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../../interfaces/YearnVault.sol";

contract YearnDaiVault {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address constant public yVaultDAI = address(0xACd43E627e64355f1861cEC6d3a6688B31a6F952);

    address public governance;
    address public strategy;

    constructor(address _strategy) public {
        governance = msg.sender;
        strategy = _strategy;
    }

    function deposit() external {
        // approve yVaultDAI use DAI
        YearnVault(yVaultDAI).depositAll();
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == strategy, "!strategy");
        uint _shares = _amount
                .mul(1e18)
                .div(YearnVault(yVaultDAI).getPricePerFullShare());

        if (_shares > IERC20(yVaultDAI).balanceOf(address(this))) {
            _shares = IERC20(yVaultDAI).balanceOf(address(this));
        }
        YearnVault(yVaultDAI).withdraw(_shares); 
    }

    function balanceOf() public view returns (uint) {
        // TODO
        return 0;
    }

    function _getPrice() internal view returns (uint p) {
        // TODO: price oracle
        return 0;
    }
}