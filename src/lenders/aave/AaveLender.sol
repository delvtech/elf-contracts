pragma solidity >=0.5.8 <0.8.0;

import "../../interfaces/IERC20.sol";
import "./interface/LendingPoolAddressesProvider.sol";
import "./interface/LendingPool.sol";
import "./interface/IAToken.sol";

interface LendingPoolCore {
    function getReserveATokenAddress(address) external view returns (address);
}

contract AaveLender {
    address public constant AAVE = address(
        0x24a42fD28C976A61Df5D00D0599C34c4f90748c8
    );

    // changed from private to public
    function depositCollateral(address _reserve, uint256 _amount)
        public
        payable
    {
        uint16 _referral = 0; // todo: change referral when done testing
        /// Retrieve LendingPool address
        LendingPoolAddressesProvider provider = LendingPoolAddressesProvider(
            AAVE
        );
        LendingPool lendingPool = LendingPool(provider.getLendingPool());

        if (msg.value == 0) {
            // give _amount approval to lendingPoolCore
            IERC20(_reserve).approve(provider.getLendingPoolCore(), _amount);
        }

        lendingPool.deposit{value: msg.value}(_reserve, _amount, _referral);
    }

    // changed from private to public
    function borrowBaseAsset(
        address _reserve,
        uint256 _amount,
        uint256 _rate
    ) public payable {
        /// 1 is stable rate, 2 is variable rate
        uint16 _referral = 0; // todo: change referral when done testing
        /// Retrieve LendingPool address
        LendingPoolAddressesProvider provider = LendingPoolAddressesProvider(
            address(AAVE)
        );
        LendingPool lendingPool = LendingPool(provider.getLendingPool());
        lendingPool.borrow(_reserve, _amount, _rate, _referral);
    }

    function redeem(address _reserve, uint256 _amount) public {
        LendingPoolAddressesProvider provider = LendingPoolAddressesProvider(
            address(AAVE)
        );
        LendingPoolCore core = LendingPoolCore(provider.getLendingPoolCore());

        address addr = core.getReserveATokenAddress(_reserve);
        IAToken aToken = IAToken(addr);

        aToken.redeem(_amount);
        IERC20(_reserve).transfer(msg.sender, _amount);
    }
}
