pragma solidity ^0.6.7;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IERC20.sol";
import "../../libraries/SafeERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SafeMath.sol";

import "./interface/ICERC20.sol";
import "./interface/ICEth.sol";
import "./interface/IComptroller.sol";

import "./interface/IUniswapV2Router02.sol";


contract APriceOracle {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 price = 400.5 ether;

    constructor() public {}

    function getPrice(address _fromToken, address _toToken)
        public
        view
        returns (uint256)
    {
        return price;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }
}

contract CompLender {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    // Comptroller address for compound.finance
    IComptroller public constant COMPOUND = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B); 

    //Only three tokens we use
    address public constant COMP  = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ICERC20 public constant cUSDC = ICERC20(address(0x39AA39c021dfbaE8faC545936693aC917d5E7563));
    ICEth   public constant cETH  = ICEth(address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5));
    address public constant USDC  = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address public constant uniswapRouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); 

    //Operating variables
    uint256 public collateralTarget = 0.75 ether;  // 75% 
    uint256 public blocksToLiquidationDangerZone = 46500;  // 24 hours =  60*60*24*7/13

    uint256 public minDAI = 100 ether; //Only lend if we have enough DAI to be worth it
    uint256 public minCompToSell = 0.5 ether; //used both as the threshold to sell but also as a trigger for harvest
    uint256 public gasFactor = 10; // multiple before triggering harvest

    address public allocator;

    APriceOracle public oracle;

    constructor(address _oracle, address _allocator) public {
        //pre-set approvals
        IERC20(COMP).approve(uniswapRouter, 1);
        IERC20(USDC).approve(address(cUSDC), 1);
        oracle = APriceOracle(_oracle);
        allocator = _allocator;
    }

    function depositAndBorrow() public {
        IWETH(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));
        if (address(this).balance > 0) {
            _lockETH(address(this).balance);
            _drawUSDC();
        }
        IERC20(USDC).safeTransfer(allocator, IERC20(USDC).balanceOf(address(this)));
    }

    function _getPrice() internal view returns(uint256 p) {
        p = oracle.getPrice(address(WETH), address(USDC));
    }

    function _lockETH(uint256 eth) internal {
        cETH.mint{value: eth}();
    }

    function _drawUSDC() public {
        (uint256 error, uint256 liquidity,) = COMPOUND.getAccountLiquidity(address(this));
        uint256 borrowed = cUSDC.borrowBalanceCurrent(address(this));
        require(error == 0, "error getting liquidity");

        // Get the total USD value of our borrowing power
        uint256 totalBorrowPower = liquidity.add(borrowed);
        // Get the amount we need to draw to utilize 75% of that borrowing power
        uint256 draw = totalBorrowPower.mul(collateralTarget).div(1e18).sub(borrowed);
        cUSDC.borrow(draw);
    }

    function _getBorrowPowerUSD() internal returns(uint256) {
        (uint256 error, uint256 liquidity,) = COMPOUND.getAccountLiquidity(address(this));
        uint256 borrowed = cUSDC.borrowBalanceCurrent(address(this));
        require(error == 0, "error getting liquidity");

        // Get the total USD value of our borrowing power
        uint256 totalBorrowPower = liquidity.add(borrowed);
        return totalBorrowPower;
    }

    function getTotalDebtAmount() public view returns(uint256) {
        return cUSDC.borrowBalanceStored(address(this));
    }

    function withdraw(uint256 eth) external {
        _withdraw(eth);
        IERC20(WETH).safeTransfer(allocator, IERC20(WETH).balanceOf(address(this)));
    }

    function _withdraw(uint256 eth) internal {
        uint256 borrowed = cUSDC.borrowBalanceCurrent(address(this));
        uint256 deposits = cETH.balanceOfUnderlying(address(this));

        // Calculate how much USDC we need to repay
        // Get ETH borrow ratio
        (,uint256 cFactor,) = COMPOUND.markets(address(cETH));
        // Calc how much USD we can borrow on our new amount of ETH
        uint256 newBorrowPowerUSD = deposits.sub(eth).mul(cFactor).div(1e18).mul(_getPrice());
        // Calc how much USDC that gives us
        uint256 newBorrowed = newBorrowPowerUSD.mul(collateralTarget).div(1e18);
        // Calc how much USDC we need to repay to get there
        uint256 repay = borrowed.sub(newBorrowed);

        // Get USDC and repay some of our loan
        IERC20(USDC).safeTransferFrom(allocator, address(this), repay);
        cUSDC.repayBorrow(repay);
        
        // Redeem cETH for the ETH desired
        require(cETH.redeemUnderlying(eth) == 0, "redeem failed");

        //  Wrap ETH
        IWETH(WETH).deposit{value: address(this).balance}();
    }

    function shouldDraw() external view returns(bool){
        uint256 deposits = cETH.exchangeRateStored().mul(cETH.balanceOf(address(this))).div(1e18);
        uint256 borrowed = cUSDC.borrowBalanceStored(address(this));
        (,uint256 cFactor,) = COMPOUND.markets(address(cETH));

        uint256 maxBorrow = deposits.mul(cFactor).div(1e18).mul(collateralTarget).div(1e18);
        return(maxBorrow > borrowed);
    }
    
    function draw() external {
        _drawUSDC();
    }

    function shouldRepay() external view returns(bool) {
        uint256 deposits = cETH.exchangeRateStored().mul(cETH.balanceOf(address(this))).div(1e18);
        uint256 borrowed = cUSDC.borrowBalanceStored(address(this));
        (,uint256 cFactor,) = COMPOUND.markets(address(cETH));

        uint256 maxBorrow = deposits.mul(cFactor).div(1e18).mul(collateralTarget).div(1e18);
        return(maxBorrow < borrowed);
    }

    function repay() external {
        uint256 borrowed = cUSDC.borrowBalanceCurrent(address(this));
        uint256 deposits = cETH.balanceOfUnderlying(address(this));

        // Calculate how much USDC we need to repay
        // Get ETH borrow ratio
        (,uint256 cFactor,) = COMPOUND.markets(address(cETH));
        // Calc how much USD we want to borrow
        uint256 maxBorrow = deposits.mul(cFactor).div(1e18).mul(collateralTarget).div(1e18);
        // Calc how much USDC we need to repay to get there
        uint256 amount = borrowed.sub(maxBorrow);

        // Get USDC and repay some of our loan
        IERC20(USDC).safeTransferFrom(allocator, address(this), amount);
        cUSDC.repayBorrow(amount);
    }

    function recycleComp() external {
        _claimComp();
        _sellComp();
        depositAndBorrow();
    }

    function _claimComp() internal {
        ICToken[] memory tokens = new ICToken[](2);
        tokens[0] =  cUSDC;
        tokens[1] =  cETH;

        COMPOUND.claimComp(address(this), tokens);
    }

    //sell COMP function
    function _sellComp() internal {
        uint256 _comp = IERC20(COMP).balanceOf(address(this));
        
        if (_comp > minCompToSell) {

            address[] memory path = new address[](3);
            path[0] = COMP;
            path[1] = WETH;

            IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(_comp, uint256(0), path, address(this), block.timestamp);
        }
    }

    receive() external payable {}

}