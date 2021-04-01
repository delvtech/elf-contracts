# Specification

The Element protocol contains the following top level contracts:

## Wrapped Position

The wrapped position contract is an abstract contract which must be implemented for any integration with an yield providing protocol. The implementor must specify functions which enable deposits, withdraws, and checks of the accumulated yield. A fully implemented wrapped position contract is deployable and can accept deposits in the underlying token which it will enable the yield on.

### YVaultAssetProxy

The YVaultAssetProxy contract is the implementation of a wrapped yearn position, for more information on yearn check their [documentation](https://docs.yearn.finance/). YVaultAssetProxy will only work with Yearn V2 vaults. It has a special feature which is called a deposit reserve, which enables it to amortize the gas costs of depositing into the yearn position if funded with underlying tokens. This deposit reserve allows depositors to earn some yearn yield but has no fees or other incentives.

## Tranche

The Tranche contract facilitates the locking and splitting functionality of the protocol, underlying tokens are deposited into it and the tranche mints principal tokens and Yield tokens to an account indicated by the depositor. The Tranche contract also inherits an ERC20 library and is the Principle token address. It will have a symbol of ELF:$wrapped_position_symbol$:$expiration time$ eg. ELF:wyUSDC:16-FEB-21.

Deposits are open any time before the expiration of the Tranche but late entries will receive less Principal tokens to pay for outstanding yield. The formula for that discount per unit deposited is the accumulated yield divided by the number of Yield tokens. Deposits cannot be made to Tranches which have accumulated more than 100% yield as it is not possible to discount the Principal token enough to pay for accumulated yield. Deposits also cannot be made after the Tranche unlock timestamp.

Please note - the Tranche contract does not handle the case of negative return gracefully do not integrate it with any yield strategy which can loose funds.

### Tranche Factory

The Tranche contract is deployed via create2 by the tranche factory contract. The tranche factory uses a callback method which means that the tranche deploy bytecode and thus the deploy bytecode hash are constant among all tranches. The create2 deployment uses expiration time and wrapped position address as nonces meaning (1) any valid tranche address is verifiable by simple hash and (2) at most one tranche per elf per expiration is deployable.

### Yield Token

The Yield token contract is deployed by the tranche contract and is a standard ERC20 except that the Tranche contract can mint or burn from it. It will have a symbol of ELV:$wrapped_position_symbol$:$expiration time$ eg. ELV:wyUSDC:16-FEB-21. Please note in the code Yield token is referred to as Interest Token.

## User Proxy

The user proxy contracts hold allowances for users and are both freezable and removable by admin accounts. If the user proxy is frozen or deleted users will still be able to withdraw, but any allowances they have set will not be accessible. This is a security feature which allows users to have more confidence setting unlimited allowances. The mint method of the user proxy allows the user to provide in calldata a list of permit calls which will be executed before the mint call.

## Convergent Curve Pool

The convert curve pool contract is an automated market maker which the Yield Space market maker with small modifications for an overview of the math please see the [paper](https://yield.is/YieldSpace.pdf). The main modification which is made is in the way that the fees are calculated, instead of calculating by changing the curvature, we calculate them by inferring the remaining yield from the curve price and then taking a percentage of that yield as a fee. This method is easier to calculate and analyse. The convergent curve pool is designed to be a Balancer V2 smart pool and so does not control any funds directly but rather just quotes prices for the main Balancer vault. LP tokens are minted and withdrawn using a proportional method, which notably does not support single token LP deposits. A percent of LP fees are paid out to Balancer V2 and more may be paid to the Element Protocol. Please note, parameter selection is complex and should be done carefully by the deployer.
