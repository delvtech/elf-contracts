pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../../interfaces/YearnVault.sol";

contract YearnTUsdVault {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant public Tusd = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address constant public yVaultTusd = address(0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a);

    address public governance;
    address public strategy;

    constructor(address _strategy) public {
        governance = msg.sender;
        strategy = _strategy;
        _approve();
    }

    function deposit() external {
        YearnVault(yVaultTusd).depositAll();
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == strategy, "!strategy");
        uint _shares = _amount
                .mul(1e18)
                .div(YearnVault(yVaultTusd).getPricePerFullShare());

        if (_shares > IERC20(yVaultTusd).balanceOf(address(this))) {
            _shares = IERC20(yVaultTusd).balanceOf(address(this));
        }
        YearnVault(yVaultTusd).withdraw(_shares); 
    }

    function balanceOf() public view returns (uint) {
        // TODO
        return 0;
    }

    function _getPrice() internal view returns (uint p) {
        // TODO: price oracle
        return 1;
    }

    function _approve() internal {
        // TODO
    }
}