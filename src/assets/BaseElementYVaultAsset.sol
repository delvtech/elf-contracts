pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

abstract contract BaseElementYVaultAsset {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public governance;
    address public strategy;
    address public vault;
    address public token;

    constructor(
        address _governance,
        address _strategy,
        address _vault,
        address _token
    ) internal {
        governance = _governance;
        strategy = _strategy;
        vault = _vault;
        token = _token;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setStrategy(address _strategy) external {
        require(msg.sender == governance, "!governance");
        strategy = _strategy;
    }

    function setVault(address _vault) external {
        require(msg.sender == governance, "!governance");
        vault = _vault;
    }

    function setToken(address _token) external {
        require(msg.sender == governance, "!governance");
        token = _token;
    }

    function deposit(uint256 _amount) external {
        require(msg.sender == strategy, "!strategy");
        IERC20(token).safeTransfer(vault, _amount);
        YearnVault(vault).deposit(_amount);
    }

    function withdraw(uint256 _amount, address _sender) external {
        require(msg.sender == strategy, "!strategy");
        uint256 _shares = _amount.div(YearnVault(vault).getPricePerFullShare());

        if (_shares > IERC20(vault).balanceOf(address(this))) {
            _shares = IERC20(vault).balanceOf(address(this));
        }
        YearnVault(vault).withdraw(_shares);
        IERC20(token).safeTransfer(_sender, _amount);
    }

    function balance() public view returns (uint256) {
        return IERC20(vault).balanceOf(address(this));
    }

    function approve() public {
        IERC20(token).approve(vault, uint256(-1));
    }
}
