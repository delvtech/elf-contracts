// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.8 <0.8.0;

contract AaveLender {
    address public constant AAVE = address(
        0x24a42fD28C976A61Df5D00D0599C34c4f90748c8
    );
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
