The following is the output of a complete test run, made on commit [`f936213`](https://github.com/element-fi/elf-contracts/commit/f93621339517a09bcff0abce7c3e8051e1438a12), from September 2nd, 2021. 

## Test Methodology

The output reflects the general best practices for unit test creation:

```
describe("Contract under test")
  describe("Feature")
      it("individual tests within a given configuration (e.g., 'caller is owner', 'caller is not owner', etc.)")
```
      
It is important that the text description accurately reflects the content of the test, and that *only* the feature describe is tested. Ideally, the concatenation of descriptive texts for any given test forms a clear, understandable narrative.

## Test Coverage

The code coverage tool instruments the Balancer V2 and Element codebase.  Since our code coverage check is intended to only account for Element code coverage, we post process this to remove the coverage results of Balancer V2.

```
Network Info
============
> HardhatEVM: v2.1.2
> network:    hardhat

Creating Typechain artifacts in directory typechain for target ethers-v5
Successfully generated Typechain artifacts!


  ConvergentCurvePool
    ✓ Normalize tokens correctly (493ms)
    ✓ Converts token units to decimal units (575ms)
    ✓ Converts token units to decimal units (312ms)
    ✓ Returns the correct fractional time (53ms)
    ✓ Mints LP in empty pool correctly (3045ms)
    ✓ Internally Mints LP correctly for underlying max (5881ms)
    ✓ Internally Mints LP correctly for the bond max (4238ms)
    ✓ Internally Mints LP correctly for Governance (4977ms)
    ✓ Internally Mints LP correctly for the bond max (4203ms)
    ✓ Internally Mints LP correctly for the underlying max (4008ms)
    ✓ Calculates fees correctly for a buy (4228ms)
    ✓ Calculates fees correctly for a sell (4359ms)
    Trades correctly
      ✓ Quotes a buy output trade correctly (4429ms)
      ✓ Quotes a sell output trade correctly (186ms)
      ✓ Quotes a buy input trade correctly (146ms)
      ✓ Quotes a sell input trade correctly (149ms)
    Balancer Fees Collected Properly
      ✓ Assigns balancer fees correctly (1365ms)
      ✓ Blocks invalid vault calls (1936ms)
    Pool Factory works
      ✓ Deploys pools (4248ms)
      ✓ Allows changing fees (42ms)
      ✓ Blocks invalid fee changes
      ✓ Allows changing governance address (45ms)
      ✓ Blocks non owner changes to governance address

  DateString
    ✓ Encodes a JAN timestamp right (42ms)
    ✓ Encodes a FEB timestamp right
    ✓ Encodes a MAR timestamp right
    ✓ Encodes a APR timestamp right
    ✓ Encodes a MAY timestamp right (40ms)
    ✓ Encodes a JUN timestamp right (40ms)
    ✓ Encodes a JUL timestamp right
    ✓ Encodes a AUG timestamp right
    ✓ Encodes a SEP timestamp right (38ms)
    ✓ Encodes a OCT timestamp right
    ✓ Encodes a NOV timestamp right (40ms)
    ✓ Encodes a DEC timestamp right
    ✓ Encodes a timestamp and writes a prefix correctly (48ms)

  erc20
    Permit function
      ✓ has a correctly precomputed typehash
      ✓ Allows valid permit call (182ms)
      ✓ Fails invalid permit call
    transfer functionality
      ✓ transfers successfully (55ms)
      ✓ does not transfer more than balance
      ✓ transferFrom successfully (98ms)
      ✓ does not decrement unlimited allowance (89ms)
      ✓ blocks invalid transferFrom

  ETHPool-Mainnet
    deposit + withdraw
      ✓ should correctly handle deposits and withdrawals (17283ms)
    balance
      ✓ should return the correct balance (2934ms)

  MockERC20YearnVault
    deposit - withdraw
      ✓ correctly handles deposits and withdrawals (1128ms)
    deposit - withdraw with rewards unlock
      ✓ correctly handles deposits and withdrawals (4441ms)

  TrancheFactory
    deployTranche
      ✓ should correctly deploy a new tranche instance
      ✓ should fail to deploy to the same address  (450ms)

  Tranche
    permit
      ✓ pt allows valid permit call (155ms)
      ✓ yt allows valid permit call (192ms)
    deposit
      ✓ should not allow new deposits after the timeout (54ms)
      ✓ should correctly handle deposits with no accrued interest (1377ms)
      ✓ should correctly handle deposits with accrued interest (2971ms)
      ✓ should block deposits with negative interest (774ms)
      ✓ Correctly deposits at 3 times (3980ms)
    withdraw
      ✓ should correctly handle Principal Token withdrawals with no accrued interest (4002ms)
      ✓ should correctly handle Principal Token withdrawals with accrued interest (4306ms)
      ✓ should correctly handle Interest Token withdrawals with no accrued interest (3892ms)
      ✓ should correctly handle Interest Token withdrawals with accrued interest (4085ms)
      ✓ should correctly handle Interest Token withdrawals with negative interest (3868ms)
      ✓ should correctly handle Principal Token withdrawals with negative interest (4262ms)
      ✓ should correctly handle Principal Token withdrawals with falsely reported negative interest (4385ms)
      ✓ Should only allow setting speedbump once and after expiration (2430ms)
      ✓ Should only allow setting the speedbump when there is a real loss (888ms)
      ✓ should correctly handle full withdrawals with no accrued interest - withdraw Interest Token, then Principal Token (4917ms)
      ✓ should correctly handle full withdrawals with no accrued interest - withdraw Principal Token, then Interest Token (6897ms)
      ✓ should correctly handle full withdrawals with accrued interest -  withdraw Interest Token, then Principal Token (4934ms)
      ✓ should correctly handle full withdrawals with accrued interest -  withdraw Principal Token, then Interest Token (6759ms)
      ✓ should prevent withdrawal of Principal Tokens and Interest Tokens before the tranche expires  (1502ms)
      ✓ should prevent withdraw of principal tokens when the interest rate is negative and speedbump hasn't been hit (2736ms)
      ✓ should prevent withdraw of principal tokens when the interest rate is negative and speedbump was hit less than 48 hours ago (3053ms)
      ✓ should prevent withdrawal of more Principal Tokens and Interest Tokens than the user has (669ms)
      ✓ Should assign names and symbols correctly

  USDCPool-Mainnet
    deposit + withdraw
      ✓ should correctly handle deposits and withdrawals (29794ms)
    balanceOfUnderlying
      ✓ should return the correct underlying balance (2604ms)
    Funded Reserve Deposit/Withdraw
      ✓ should correctly handle deposits and withdrawals (20866ms)

  UserProxyTests
    ✓ Successfully derives tranche contract address
First Mint 278910
Repeat Mint 142062
New User First mint 172048
    ✓ Successfully mints (7878ms)
    ✓ Blocks Weth withdraw function when using USDC (558ms)
    Deprecation function
      ✓ Blocks deprecation by non owners (162ms)
      ✓ Allows deprecation by the owner (849ms)
    WETH mint
      ✓ Reverts with value mismatch
      ✓ Correctly mints with WETH (3606ms)
      ✓ Correctly redeems weth pt + yt for eth (11305ms)
      ✓ Blocks weth redemption when both assets are 0 (39ms)
      ✓ Blocks non weth incoming eth transfers (169ms)
    erc20 Permit mint
      ✓ Correctly mints with permit (4201ms)

  Wrapped Position
    Version locked deployments
      ✓ Wont deploy YAssetProxy with a v4 yearn vault (703ms)
    balanceOfUnderlying
      ✓ should return the correct balance (912ms)
    deposit
      ✓ should correctly track deposits (6938ms)
    transfer
      ✓ should correctly transfer value (1840ms)
    withdraw
      ✓ should correctly withdraw value (6539ms)
    Reserve deposit and withdraw
      ✓ Successfully deposits (817ms)
      ✓ Successfully withdraws (2434ms)
    Wrapped Yearn Vault v4 upgrade
      ✓ Won't deploy on a v3 wrapped position (259ms)
BigNumber { _hex: '0x2dc6bf', _isBigNumber: true }
      ✓ Reserve deposits (208ms)
      ✓ withdraws with the correct ratio (190ms)

  zapTrancheHop
    rescueTokens
      ✓ should correctly rescue ERC20 (2087ms)
    hopToTranche
      ✓ should revert if the contract is frozen (1543ms)
      ✓ should fail to hop with insufficient PT minted (2686ms)
      ✓ should fail to hop with insufficient YT minted (3026ms)
      ✓ should correctly hop tranches (12695ms)

  zapYearnShares
    zapSharesIn
      ✓ should fail with incorrect PT expected (2694ms)
      ✓ should correctly zap shares in (7903ms)


  106 passing (8m)
  
  ----------------------------------------------|----------|----------|----------|----------|----------------|
File                                          |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
----------------------------------------------|----------|----------|----------|----------|----------------|
 contracts/                                   |    93.18 |    84.06 |    92.65 |    92.98 |                |
  ConvergentCurvePool.sol                     |    87.72 |       75 |      100 |    86.98 |... 696,715,736 |
  InterestToken.sol                           |    91.67 |       50 |    85.71 |    92.31 |             76 |
  Tranche.sol                                 |    98.59 |      100 |     87.5 |    98.61 |            127 |
  UserProxy.sol                               |    97.67 |    83.33 |       90 |    97.83 |             59 |
  WrappedPosition.sol                         |    95.45 |      100 |     87.5 |    95.45 |             71 |
  YVaultAssetProxy.sol                        |    97.18 |    94.44 |    92.31 |    97.18 |        251,252 |
  YVaultV4AssetProxy.sol                      |      100 |       75 |      100 |      100 |                |
 contracts/factories/                         |      100 |       75 |      100 |      100 |                |
  ConvergentPoolFactory.sol                   |      100 |      100 |      100 |      100 |                |
  InterestTokenFactory.sol                    |      100 |      100 |      100 |      100 |                |
  TrancheFactory.sol                          |      100 |       50 |      100 |      100 |                |
 contracts/interfaces/                        |      100 |      100 |      100 |      100 |                |
  IERC20.sol                                  |      100 |      100 |      100 |      100 |                |
  IERC20Decimals.sol                          |      100 |      100 |      100 |      100 |                |
  IERC20Permit.sol                            |      100 |      100 |      100 |      100 |                |
  IInterestToken.sol                          |      100 |      100 |      100 |      100 |                |
  IInterestTokenFactory.sol                   |      100 |      100 |      100 |      100 |                |
  ITranche.sol                                |      100 |      100 |      100 |      100 |                |
  ITrancheFactory.sol                         |      100 |      100 |      100 |      100 |                |
  IWETH.sol                                   |      100 |      100 |      100 |      100 |                |
  IWrappedPosition.sol                        |      100 |      100 |      100 |      100 |                |
  IYearnVault.sol                             |      100 |      100 |      100 |      100 |                |
 contracts/libraries/                         |    98.17 |    90.91 |       96 |    98.06 |                |
  Authorizable.sol                            |     87.5 |      100 |     87.5 |       90 |             45 |
  DateString.sol                              |    98.36 |    95.83 |      100 |    98.08 |            154 |
  ERC20Permit.sol                             |      100 |    81.25 |      100 |      100 |                |
  ERC20PermitWithSupply.sol                   |      100 |      100 |      100 |      100 |                |
 contracts/zaps/                              |    95.12 |       75 |    83.33 |    95.35 |                |
  ZapTrancheHop.sol                           |      100 |       80 |      100 |      100 |                |
  ZapYearnShares.sol                          |    88.24 |    66.67 |    66.67 |    88.89 |          37,99 |
----------------------------------------------|----------|----------|----------|----------|----------------|
All files                                     |    97.70 |    89.56 |    95.78 |    97.80 |                |
----------------------------------------------|----------|----------|----------|----------|----------------|
```
