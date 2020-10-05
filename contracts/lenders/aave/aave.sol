pragma solidity >=0.4.22 <0.8.0;

contract aave {
   /* function depositCollateral(address _reserve, uint256 _amount) private {
        uint256 _referral = 0; // todo: change referral when done testing
        /// Retrieve LendingPool address
        LendingPoolAddressesProvider provider = LendingPoolAddressesProvider(address(aave));
        LendingPool lendingPool = LendingPool(provider.getLendingPool());
        lendingPool.deposit{ value: msg.value }(_reserve, msg.value, _referral)

    }

    function borrowBaseAsset(address _reserve, address _amount) private {
        /// 1 is stable rate, 2 is variable rate
        uint256 _rate = 2;
        uint256 _referral = 0; // todo: change referral when done testing
        /// Retrieve LendingPool address
        LendingPoolAddressesProvider provider = LendingPoolAddressesProvider(address(aave));
        LendingPool lendingPool = LendingPool(provider.getLendingPool());
        lendingPool.borrow(_reserve, _amount, _rate, _referral);
    }*/
}