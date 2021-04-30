# Specification

The Element protocol contains the following top-level contracts:

## Wrapped Position

The wrapped position contract is an abstract contract that must be implemented for any integration with a yield-generating protocol. The implementor must specify functions that enable deposits, withdraws, and checks of the accumulated yield. A fully implemented wrapped position contract is deployable and can accept deposits in the underlying token which it will enable the yield on.

### YVaultAssetProxy

The YVaultAssetProxy contract is the implementation of a wrapped yearn position, for more information on Yearn, check their [documentation](https://docs.yearn.finance/). YVaultAssetProxy will only work with Yearn V2 vaults. It has a special feature which is called a deposit reserve, which enables it to amortize the gas costs of depositing into the yearn position if funded with underlying tokens. This deposit reserve allows depositors to earn some yearn yield but has no fees or other incentives.

## Tranche

The Tranche contract facilitates the locking and splitting functionality of the protocol, underlying tokens are deposited into it and the tranche mints Principal tokens and Yield tokens to an account indicated by the depositor. The Tranche contract also inherits an ERC20 library and is the Principal token address. It will have a symbol of `eP:$wrapped_position_symbol$:$expiration time$ eg. eP:wyUSDC:16-FEB-21-GMT`.

Deposits are open at any time before the expiration of the Tranche but late entries will receive fewer Principal tokens to pay for outstanding yield. The formula for the discount per unit deposited is the accumulated yield divided by the number of Yield tokens. Deposits cannot be made to Tranches that have accumulated more than 100% yield as it is not possible to discount the Principal token enough to pay for accumulated yield. Deposits also cannot be made after the Tranche unlock timestamp has passed.

*Important Note:* If the tranche contract's underlying has accumulated negative interest (ie lost money) the tranche cannot process withdraws until a function called speedbump is called. Once the speedbump has been hit the tranche can only process negative interest rate redemptions 48 hours after the speedbump was hit, but can continue to process any positive interest rate redemptions. If the speedbump is hit and it has been 48 hours and the yield position still has a loss, then principal tokens can be redeemed pro rata for any remaining funds. The speedbump can only be hit once. No integration should incur losses as part of a normal course of operations.

### Tranche Factory

The Tranche contract is deployed via [create2](https://eips.ethereum.org/EIPS/eip-1014) by the tranche factory contract. The tranche factory uses a callback method which means that the tranche deploy bytecode and thus, the deploy bytecode hash is constant among all tranches. The create2 deployment uses the expiration time and wrapped position address as nonces, meaning (1) any valid tranche address is verifiable by simple hash, and (2) at most one tranche per elf per expiration is deployable.

### Yield Token

The Yield token contract is deployed by the tranche contract and is a standard ERC20 except that the Tranche contract can mint or burn from it. It will have a symbol of `eY:$wrapped_position_symbol$:$expiration` time$ eg. `eY:wyUSDC:16-FEB-21-GMT`. Please note that in the code, the Yield token is referred to as Interest Token.

## User Proxy

The user proxy contracts hold allowances for users and are both freezable and removable by admin accounts. If the user proxy is frozen or deleted, users will still be able to withdraw but any allowances they have set will not be accessible. This is a security feature that allows users to have more confidence in setting unlimited allowances. The mint method of the user proxy allows the user to provide a list of permit calls (in calldata) that will be executed before the mint call.

## Convergent Curve Pool

The convert curve pool contract is an automated market maker (AMM), which combines the Yield Space market maker with some additional small modifications. For an overview of the math, please see the Yield Space [paper](https://yield.is/YieldSpace.pdf). The main modification is in the way that the fees are calculated. Instead of calculating by changing the curvature, we calculate them by inferring the remaining yield from the curve price and then taking a percentage of that yield as a fee. This method is easier to calculate and analyze. The convergent curve pool is designed to be a Balancer V2 smart pool and thus does not control any funds directly but rather just quotes the prices for the main Balancer vault. LP tokens are minted and withdrawn using a proportional method, which notably does not support single token LP deposits. A percent of LP fees are paid out to Balancer V2 and more may be paid out to the Element Protocol. Please note that parameter selection is complex and should be done carefully by the deployer.
