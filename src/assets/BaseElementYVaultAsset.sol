pragma solidity >=0.5.8 <0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/YearnVault.sol";
import "../interfaces/IBPool.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

abstract contract BaseElementYVaultAsset {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    YearnVault public vault;

    address public governance;
    address public allocator;
    address public token;

    // address to redeposit vault shares
    address public secondary;

    constructor(
        address _governance,
        address _allocator,
        address _vault,
        address _token
    ) internal {
        governance = _governance;
        allocator = _allocator;
        vault = YearnVault(_vault);
        token = _token;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setAllocator(address _allocator) external {
        require(msg.sender == governance, "!governance");
        allocator = _allocator;
    }

    function setVault(address _vault) external {
        require(msg.sender == governance, "!governance");
        vault = YearnVault(_vault);
    }

    function setToken(address _token) external {
        require(msg.sender == governance, "!governance");
        token = _token;
    }

    function deposit(uint256 _amount) external {
        require(msg.sender == allocator, "!allocator");
        IERC20(token).safeApprove(address(vault), 0);
        IERC20(token).safeApprove(address(vault), _amount);
        vault.deposit(_amount);

        if (secondary != address(0)) {
            uint256 lpTokensOut = IBPool(secondary).joinswapExternAmountIn(
                address(vault),
                _amount,
                0
            );

            IBPool(secondary).transfer(address(msg.sender), lpTokensOut);
        } else {
            vault.transfer(address(msg.sender), vault.balanceOf(address(this)));
        }
    }

    function withdraw(uint256 _amount, address _sender) external {
        require(msg.sender == allocator, "!allocator");
        uint256 shares;

        if (secondary != address(0)) {
            uint256 tokenAmountOut = IBPool(secondary).exitswapPoolAmountIn(
                address(vault),
                IBPool(secondary).balanceOf(address(this)),
                0
            );
            shares = tokenAmountOut.div(vault.getPricePerFullShare());
        } else {
            shares = _amount.div(vault.getPricePerFullShare());
        }

        vault.withdraw(shares);

        IERC20(token).safeTransfer(
            _sender,
            IERC20(token).balanceOf(address(this))
        );
    }

    function balance() public view returns (uint256) {
        return vault.balanceOf(address(allocator));
    }

    function approve() public {
        IERC20(token).approve(address(vault), uint256(-1));
    }
}
