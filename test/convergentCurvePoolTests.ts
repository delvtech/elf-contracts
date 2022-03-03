import "module-alias/register";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import chai, { expect } from "chai";
import chaiAlmost from "chai-almost";
import { BigNumber, BigNumberish, providers } from "ethers";
import { formatEther } from "ethers/lib/utils";
import { ethers, network, waffle } from "hardhat";
import { deployBalancerVault } from "test/helpers/deployBalancerVault";
import { deployConvergentCurvePool } from "test/helpers/deployConvergentCurvePool";
import {
  EthPoolMainnetInterface,
  loadEthPoolMainnetFixture,
} from "test/helpers/deployer";
import { ConvergentPoolFactory } from "typechain/ConvergentPoolFactory";
import { ConvergentPoolFactory__factory } from "typechain/factories/ConvergentPoolFactory__factory";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { TestVault__factory } from "typechain/factories/TestVault__factory";
import { TestConvergentCurvePool } from "typechain/TestConvergentCurvePool";
import { TestERC20 } from "typechain/TestERC20";
import { Vault } from "typechain/Vault";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { TestConvergentCurvePool__factory } from "typechain/factories/TestConvergentCurvePool__factory";
import { impersonate, stopImpersonating } from "./helpers/impersonate";

const { provider } = waffle;

// we need to use almost for the onSwap tests since `hardhat coverage` compiles the contracts
// slightly differently which causes slightly different fixedpoint logic.
// normal tests are also failing on CI now, setting the tolerance to 10^-4 so that they will pass.
// TODO: figure out if we can only apply tolerance to the coverage tests.
// const DEFAULT_CHAI_ALMOST_TOLERANCE = 10e-4;
// const tolerance = process.env.COVERAGE ? DEFAULT_CHAI_ALMOST_TOLERANCE : 0;
chai.use(chaiAlmost(20e-4));

describe("ConvergentCurvePool", function () {
  const BOND_DECIMALS = 17;
  const BASE_DECIMALS = 6;
  const SECONDS_IN_YEAR = 31536000;
  const inForOutType = 0;
  const outForInType = 1;

  const fakeAddress = "0x5a0b54d5dc17e0aadc383d2db43b0a0d3e029c4c";
  let fixture: EthPoolMainnetInterface;
  let accounts: SignerWithAddress[];
  let balancerSigner: SignerWithAddress;
  let elementSigner: SignerWithAddress;
  let elementAddress: string;
  let tokenSigner: SignerWithAddress;
  let poolContract: TestConvergentCurvePool;
  let startTimestamp: number;
  let expirationTime: number;
  let baseAssetContract: TestERC20;
  let bondAssetContract: TestERC20;
  let balancerVaultContract: Vault;

  const reserveBond = ethers.utils.parseUnits("12000", BOND_DECIMALS);
  const reserveUnderlying = ethers.utils.parseUnits("10000", BASE_DECIMALS);

  async function getTimestamp() {
    return (await ethers.provider.getBlock("latest")).timestamp;
  }

  // An interface to allow us to access the ethers log return
  interface LogData {
    event: string;

    // TODO: figure out what this is.
    data: unknown;
  }

  // A partially extended interface for the post mining transaction receipt
  interface PostExecutionTransactionReceipt
    extends providers.TransactionReceipt {
    events: LogData[];
  }

  async function mineTx(
    tx: Promise<providers.TransactionResponse>
  ): Promise<PostExecutionTransactionReceipt> {
    return (await tx).wait() as Promise<PostExecutionTransactionReceipt>;
  }

  function newBigNumber(data: number): BigNumber {
    const cast = BigNumber.from(data);
    return cast;
  }

  async function resetPool() {
    ({ poolContract } = await deployConvergentCurvePool(
      elementSigner,
      balancerVaultContract,
      baseAssetContract,
      bondAssetContract,
      {
        swapFee: "0.05",
        durationInSeconds: SECONDS_IN_YEAR,
        expiration: expirationTime,
      }
    ));
  }

  before(async function () {
    await createSnapshot(provider);
    fixture = await loadEthPoolMainnetFixture();
    const wethAddress = fixture.weth.address;
    startTimestamp = await getTimestamp();
    expirationTime = startTimestamp + SECONDS_IN_YEAR;

    accounts = await ethers.getSigners();
    [balancerSigner, elementSigner, tokenSigner] = accounts;
    const ERC20Deployer = new TestERC20__factory(tokenSigner);
    bondAssetContract = await ERC20Deployer.deploy(
      "Bond",
      "EL1Y",
      BOND_DECIMALS
    );
    baseAssetContract = await ERC20Deployer.deploy(
      "Stablecoin",
      "USDC",
      BASE_DECIMALS
    );

    elementAddress = await elementSigner.getAddress();

    balancerVaultContract = await deployBalancerVault(
      balancerSigner,
      wethAddress
    );
    await balancerVaultContract.setRelayerApproval(
      balancerSigner.address,
      elementAddress,
      true
    );

    ({ poolContract } = await deployConvergentCurvePool(
      elementSigner,
      balancerVaultContract,
      baseAssetContract,
      bondAssetContract,
      {
        swapFee: "0.05",
        durationInSeconds: SECONDS_IN_YEAR,
        expiration: expirationTime,
      }
    ));
  });

  after(function () {
    restoreSnapshot(provider);
  });

  it("Normalize tokens correctly", async function () {
    const one = ethers.utils.parseUnits("1", 18);
    // We check that the same decimals is a no opp
    const no_opp = await poolContract.normalize(one, 18, 18);
    expect(no_opp).to.be.eq(one);
    // We check that it reduces decimals correctly
    const bp = await poolContract.normalize(one, 18, 14);
    expect(bp).to.be.eq(ethers.utils.parseUnits("1", 14));
    // We check that it increases decimals  correctly
    const x100 = await poolContract.normalize(one, 18, 20);
    expect(x100).to.be.eq(ethers.utils.parseUnits("1", 20));
  });

  function getRandomInt(max: number) {
    return Math.floor(Math.random() * Math.floor(max));
  }

  it("Converts token units to decimal units", async function () {
    // Check that a random bond unit is correctly decimal encoded
    const tokenAmount = getRandomInt(1000);
    let normalized = await poolContract.tokenToFixed(
      ethers.utils.parseUnits(tokenAmount.toString(), BOND_DECIMALS),
      bondAssetContract.address
    );
    expect(normalized).to.be.eq(
      ethers.utils.parseUnits(tokenAmount.toString(), 18)
    );
    // Check that the underlying token normalizes correctly
    normalized = await poolContract.tokenToFixed(
      ethers.utils.parseUnits(tokenAmount.toString(), BASE_DECIMALS),
      baseAssetContract.address
    );
    expect(normalized).to.be.eq(
      ethers.utils.parseUnits(tokenAmount.toString(), 18)
    );
  });

  it("Converts token units to decimal units", async function () {
    // Check that a random bond unit is correctly decimal encoded
    const tokenAmount = getRandomInt(1000);
    let normalized = await poolContract.tokenToFixed(
      ethers.utils.parseUnits(tokenAmount.toString(), BOND_DECIMALS),
      bondAssetContract.address
    );
    expect(normalized).to.be.eq(
      ethers.utils.parseUnits(tokenAmount.toString(), 18)
    );
    // Check that the underlying token normalizes correctly
    normalized = await poolContract.tokenToFixed(
      ethers.utils.parseUnits(tokenAmount.toString(), BASE_DECIMALS),
      baseAssetContract.address
    );
    expect(normalized).to.be.eq(
      ethers.utils.parseUnits(tokenAmount.toString(), 18)
    );
  });

  it("Returns the correct fractional time", async function () {
    // We set the next block's time to be the start time + 1/2 * SECONDS_IN_YEAR
    await network.provider.send("evm_setNextBlockTimestamp", [
      startTimestamp + SECONDS_IN_YEAR / 2,
    ]);
    await network.provider.send("evm_mine");

    // We now call the function which returns 1 - t, which should be 0.5
    const exponent = await poolContract.getYieldExponent();
    expect(exponent).to.be.eq(ethers.utils.parseUnits("0.5", 18));
  });

  it("Mints LP in empty pool correctly", async function () {
    await resetPool();
    // We use the mintLP function in tes
    const oneThousand = ethers.utils.parseUnits("1000", 18);
    const result = await mineTx(
      poolContract.mintLP(oneThousand, oneThousand, [0, 0], accounts[0].address)
    );
    // Check that it returns the right data using the event hack
    const returned = result.events.filter(
      (event) => event.event == "UIntReturn"
    );
    expect(returned[0].data).to.be.eq(oneThousand);
    expect(returned[1].data).to.be.eq(newBigNumber(0));
    // Check the LP balance
    const balance = await poolContract.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(oneThousand);
  });

  // We test the mint functionality where the underlying should be fully
  // consumed
  it("Internally Mints LP correctly for underlying max", async function () {
    await resetPool();
    const oneThousand = ethers.utils.parseUnits("1000", 18);
    // Set the current total supply to 1000 lp tokens
    await mineTx(poolContract.setLPBalance(accounts[1].address, oneThousand));
    // We use the mintLP function in tes
    const fiveHundred = ethers.utils.parseUnits("500", 18);
    const result = await mineTx(
      poolContract.mintLP(
        oneThousand,
        oneThousand,
        [oneThousand, fiveHundred],
        accounts[0].address
      )
    );
    // Check that it returns the right data using the event hack
    const returned = result.events.filter(
      (event) => event.event == "UIntReturn"
    );
    expect(returned[0].data).to.be.eq(oneThousand);
    expect(returned[1].data).to.be.eq(fiveHundred);
    // Check the LP balance
    const balance = await poolContract.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(oneThousand);
    const totalSupply = await poolContract.totalSupply();
    expect(totalSupply).to.be.eq(ethers.utils.parseUnits("2000", 18));
  });

  // We test the mint functionality where the bond should be fully consumed
  it("Internally Mints LP correctly for the bond max", async function () {
    await resetPool();
    const twoThousand = ethers.utils.parseUnits("2000", 18);
    const oneThousand = twoThousand.div(2);
    // Set the current total supply to 1000 lp tokens
    await mineTx(poolContract.setLPBalance(accounts[1].address, oneThousand));
    // We use the mintLP function in tes
    const fiveHundred = ethers.utils.parseUnits("500", 18);
    const eightHundred = ethers.utils.parseUnits("800", 18);
    const result = await mineTx(
      poolContract.mintLP(
        twoThousand,
        eightHundred,
        [oneThousand, fiveHundred],
        accounts[0].address
      )
    );
    // Check that it returns the right data using the event hack
    const returned = result.events.filter(
      (event) => event.event == "UIntReturn"
    );
    const sixteenHundred = ethers.utils.parseUnits("1600", 18);
    expect(returned[0].data).to.be.eq(sixteenHundred);
    expect(returned[1].data).to.be.eq(eightHundred);
    // Check the LP balance
    const balance = await poolContract.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(sixteenHundred);
    const totalSupply = await poolContract.totalSupply();
    expect(totalSupply).to.be.eq(oneThousand.add(sixteenHundred));
  });

  // We test the burn functionality where the bond should be fully consumed
  it("Internally Burns LP correctly for the underlying max", async function () {
    await resetPool();
    const oneThousand = ethers.utils.parseUnits("1000", 18);
    // Set the current total supply to 1000 lp tokens
    await mineTx(poolContract.setLPBalance(accounts[0].address, oneThousand));
    const fiveHundred = ethers.utils.parseUnits("500", 18);
    const twoFifty = fiveHundred.div(2);
    const result = await mineTx(
      poolContract.burnLP(
        fiveHundred,
        [oneThousand, fiveHundred],
        accounts[0].address
      )
    );
    // The call should have released 500 underlying and 250 bond
    const returned = result.events.filter(
      (event) => event.event == "UIntReturn"
    );
    expect(returned[0].data).to.be.eq(fiveHundred);
    expect(returned[1].data).to.be.eq(twoFifty);
    // The call should have burned 50% of the LP tokens to produce this
    const balance = await poolContract.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(fiveHundred);
    const totalSupply = await poolContract.totalSupply();
    expect(totalSupply).to.be.eq(fiveHundred);
  });

  // We test the assigned trade fee when buying a bond
  it("Calculates fees correctly for a buy", async function () {
    await resetPool();
    const amount = ethers.utils.parseUnits("11000", BOND_DECIMALS);
    const inputUnderlying = ethers.utils.parseUnits("10000", BASE_DECIMALS);

    // Check the case when this is an output trade
    let result = await mineTx(
      poolContract.assignTradeFee(
        inputUnderlying,
        amount,
        bondAssetContract.address,
        false
      )
    );
    let returned = result.events.filter((event) => event.event == "UIntReturn");
    expect(returned[0].data).to.be.eq(
      ethers.utils.parseUnits("10950", BOND_DECIMALS)
    );
    // Check the stored fees
    const feeBond = await poolContract.feesBond();
    //
    expect(feeBond).to.be.eq(ethers.utils.parseUnits("50"));

    // Check the case when this is an input trade
    result = await mineTx(
      poolContract.assignTradeFee(
        inputUnderlying,
        amount,
        bondAssetContract.address,
        true
      )
    );
    returned = result.events.filter((event) => event.event == "UIntReturn");
    expect(returned[0].data).to.be.eq(
      ethers.utils.parseUnits("10050", BASE_DECIMALS)
    );
    // Check the stored fees
    const feeUnderlying = await poolContract.feesUnderlying();
    expect(feeUnderlying).to.be.eq(ethers.utils.parseUnits("50"));
  });

  // We test the assigned trade fee when selling a bond
  it("Calculates fees correctly for a sell", async function () {
    await resetPool();
    const inputBond = ethers.utils.parseUnits("11000", BOND_DECIMALS);
    const amount = ethers.utils.parseUnits("10000", BASE_DECIMALS);

    // Check the case when this is an input trade
    let result = await mineTx(
      poolContract.assignTradeFee(
        inputBond,
        amount,
        baseAssetContract.address,
        false
      )
    );
    let returned = result.events.filter((event) => event.event == "UIntReturn");
    expect(returned[0].data).to.be.eq(
      ethers.utils.parseUnits("9950", BASE_DECIMALS)
    );
    // Check the stored fees
    const feeUnderlying = await poolContract.feesUnderlying();
    // This will be recorded internally as 18 point
    expect(feeUnderlying).to.be.eq(ethers.utils.parseUnits("50"));
    // Check the case when this is an false trade
    result = await mineTx(
      poolContract.assignTradeFee(
        inputBond,
        amount,
        baseAssetContract.address,
        true
      )
    );
    returned = result.events.filter((event) => event.event == "UIntReturn");
    expect(returned[0].data).to.be.eq(
      ethers.utils.parseUnits("11050", BOND_DECIMALS)
    );
    // Check the stored fees
    const feesBond = await poolContract.feesBond();
    // Internally recorded as 18 fixed point
    expect(feesBond).to.be.eq(ethers.utils.parseUnits("50"));
  });

  // We get a series of quotes for specifically checked trades

  describe("Trades correctly", async () => {
    before(async () => {
      impersonate(balancerVaultContract.address);
    });
    after(async () => {
      stopImpersonating(balancerVaultContract.address);
    });
    it("Quotes a buy output trade correctly", async function () {
      await resetPool();
      const quote = await poolContract
        .connect(balancerVaultContract.address)
        .callStatic.onSwap(
          {
            tokenIn: baseAssetContract.address,
            tokenOut: bondAssetContract.address,
            amount: ethers.utils.parseUnits("100", BASE_DECIMALS),
            kind: inForOutType,
            // Misc data
            poolId:
              "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
            lastChangeBlock: BigNumber.from(0),
            from: fakeAddress,
            to: fakeAddress,
            userData: "0x",
          },
          reserveUnderlying,
          reserveBond
        );
      const result = Number(formatEther(quote));
      const expectedValue = 10.8572076454026339518;
      expect(result).to.be.almost(expectedValue);
    });

    it("Quotes a sell output trade correctly", async function () {
      const quote = await poolContract
        .connect(balancerVaultContract.address)
        .callStatic.onSwap(
          {
            tokenIn: bondAssetContract.address,
            tokenOut: baseAssetContract.address,
            amount: ethers.utils.parseUnits("100", BOND_DECIMALS),
            kind: inForOutType,
            // Misc data
            poolId:
              "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
            lastChangeBlock: BigNumber.from(0),
            from: fakeAddress,
            to: fakeAddress,
            userData: "0x",
          },
          reserveBond,
          reserveUnderlying
        );
      expect(quote.toNumber()).to.be.almost(
        ethers.utils.parseUnits("90.434755", BASE_DECIMALS).toNumber(),
        10
      );
    });

    it("Quotes a buy input trade correctly", async function () {
      const quote = await poolContract
        .connect(balancerVaultContract.address)
        .callStatic.onSwap(
          {
            tokenIn: baseAssetContract.address,
            tokenOut: bondAssetContract.address,
            amount: ethers.utils.parseUnits("200", BOND_DECIMALS),
            kind: outForInType,
            // Misc data
            poolId:
              "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
            lastChangeBlock: BigNumber.from(0),
            from: fakeAddress,
            to: fakeAddress,
            userData: "0x",
          },
          reserveUnderlying,
          reserveBond
        );
      expect(quote.toNumber()).to.be.almost(
        ethers.utils.parseUnits("184.972608", BASE_DECIMALS).toNumber(),
        20
      );
    });

    it("Quotes a sell input trade correctly", async function () {
      const quote = await poolContract
        .connect(balancerVaultContract.address)
        .callStatic.onSwap(
          {
            tokenIn: bondAssetContract.address,
            tokenOut: baseAssetContract.address,
            amount: ethers.utils.parseUnits("150", BASE_DECIMALS),
            kind: outForInType,
            // Misc data
            poolId:
              "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
            lastChangeBlock: BigNumber.from(0),
            from: fakeAddress,
            to: fakeAddress,
            userData: "0x",
          },
          reserveBond,
          reserveUnderlying
        );
      const result = Number(formatEther(quote));
      const expectedValue = 16.6279570802359854161;
      expect(result).to.be.almost(expectedValue);
    });
  });

  describe("Balancer Fees Collected Properly", async () => {
    let poolContract: TestConvergentCurvePool;
    let aliasedVault: TestConvergentCurvePool;

    before(async () => {
      const testVaultFactory = new TestVault__factory(tokenSigner);
      const testVault = await testVaultFactory.deploy();

      const elementAddress = await tokenSigner.getAddress();
      const baseAssetSymbol = await baseAssetContract.symbol();
      const curvePoolDeployer = new TestConvergentCurvePool__factory(
        tokenSigner
      );

      const startTimestamp = await getTimestamp();
      const expirationTime = startTimestamp + SECONDS_IN_YEAR;

      poolContract = await curvePoolDeployer.deploy(
        baseAssetContract.address,
        bondAssetContract.address,
        expirationTime,
        SECONDS_IN_YEAR,
        testVault.address,
        ethers.utils.parseEther("0.05"),
        balancerSigner.address,
        `Element ${baseAssetSymbol} - fy${baseAssetSymbol}`,
        `${baseAssetSymbol}-fy${baseAssetSymbol}`
      );

      beforeEach(async () => {
        await createSnapshot(provider);
      });
      afterEach(async () => {
        await restoreSnapshot(provider);
      });

      aliasedVault = TestConvergentCurvePool__factory.connect(
        testVault.address,
        tokenSigner
      );
    });

    // This test calls through the test balancer vault to use the join/leave pool interface
    // directly, it checks that the balancer fee is assessed correctly
    it("Assigns balancer fees correctly", async () => {
      const poolId = await poolContract.getPoolId();
      // First create some pretend fees
      const ten = ethers.utils.parseUnits("10", 18);
      // Mint some lp to avoid init case
      await poolContract.setLPBalance(tokenSigner.address, 1);
      // We set the accumulated fees
      await poolContract.setFees(ten, ten);

      const bondFirst = BigNumber.from(bondAssetContract.address).lt(
        BigNumber.from(baseAssetContract.address)
      );
      const bondIndex = bondFirst ? 0 : 1;
      const baseIndex = bondFirst ? 1 : 0;
      const reserves: BigNumberish[] = [0, 0];
      reserves[bondIndex] = ethers.utils.parseUnits("50", BOND_DECIMALS);
      reserves[baseIndex] = ethers.utils.parseUnits("100", BASE_DECIMALS);
      const lp_deposit: BigNumberish[] = [0, 0];
      lp_deposit[bondIndex] = ethers.utils.parseUnits("5", BOND_DECIMALS);
      lp_deposit[baseIndex] = ethers.utils.parseUnits("10", BASE_DECIMALS);

      // Mint some LP
      let data = await aliasedVault.callStatic.onJoinPool(
        poolId,
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        reserves,
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(["uint256[]"], [lp_deposit])
      );
      // Check the returned fees
      expect(data[1][0]).to.be.eq(ethers.utils.parseUnits("1", BASE_DECIMALS));
      expect(data[1][1]).to.be.eq(ethers.utils.parseUnits("1", BOND_DECIMALS));
      // We run the call but state changing
      await aliasedVault.onJoinPool(
        poolId,
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        reserves,
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(["uint256[]"], [lp_deposit])
      );
      // We check the state
      expect(await poolContract.feesUnderlying()).to.be.eq(0);
      expect(await poolContract.feesBond()).to.be.eq(0);
      // Note swap fee = 0.05 implies 1/20 as ratio
      expect(await poolContract.governanceFeesUnderlying()).to.be.eq(
        ten.div(20)
      );
      expect(await poolContract.governanceFeesBond()).to.be.eq(ten.div(20));
      // We run another trade to ensure fees are not charged when no lp
      // is minted
      data = await aliasedVault.callStatic.onJoinPool(
        poolId,
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        reserves,
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(["uint256[]"], [lp_deposit])
      );
      // Check the returned fees
      expect(data[1][0]).to.be.eq(0);
      expect(data[1][1]).to.be.eq(0);
    });
    it("Allows the governance to collect realized fees", async () => {
      const poolId = await poolContract.getPoolId();
      // First create some pretend fees
      const ten = ethers.utils.parseUnits("10", 18);
      // Mint some lp to avoid init case
      await poolContract.setLPBalance(tokenSigner.address, 1);
      // We set the accumulated fees
      await poolContract.setFees(ten, ten);

      const bondFirst = BigNumber.from(bondAssetContract.address).lt(
        BigNumber.from(baseAssetContract.address)
      );
      const bondIndex = bondFirst ? 0 : 1;
      const baseIndex = bondFirst ? 1 : 0;
      const reserves: BigNumberish[] = [0, 0];
      reserves[bondIndex] = ethers.utils.parseUnits("50", BOND_DECIMALS);
      reserves[baseIndex] = ethers.utils.parseUnits("100", BASE_DECIMALS);
      const lp_deposit: BigNumberish[] = [0, 0];
      lp_deposit[bondIndex] = ethers.utils.parseUnits("5", BOND_DECIMALS);
      lp_deposit[baseIndex] = ethers.utils.parseUnits("10", BASE_DECIMALS);
      // This call changes the state
      await aliasedVault.onJoinPool(
        poolId,
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        reserves,
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(["uint256[]"], [lp_deposit])
      );
      // now we simulate a withdraw to see what the return values are
      const data = await aliasedVault.callStatic.onExitPool(
        poolId,
        await poolContract.governance(),
        fakeAddress,
        reserves,
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(["uint256"], [0])
      );
      // we check that the amounts out are the whole fees
      expect(data[0][bondIndex]).to.be.eq(
        ethers.utils.parseUnits("0.5", BOND_DECIMALS)
      );
      expect(data[0][baseIndex]).to.be.eq(
        ethers.utils.parseUnits("0.5", BASE_DECIMALS)
      );
    });
    it("Blocks invalid vault calls", async () => {
      const poolId = await poolContract.getPoolId();
      // First create some pretend fees
      const ten = ethers.utils.parseUnits("10", 18);
      const five = ethers.utils.parseUnits("5", 18);
      // Mint some lp to avoid init case
      await poolContract.setLPBalance(tokenSigner.address, 1);
      // We set the accumulated fees
      await poolContract.setFees(ten, ten);

      // Called not from the vault
      // Blocked join
      let tx = poolContract.onJoinPool(
        poolId,
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        [ten.mul(10), five.mul(10)],
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(
          ["uint256[]"],
          [[ten.mul(10), five.mul(10)]]
        )
      );
      await expect(tx).to.be.revertedWith("Non Vault caller");
      // blocked exit
      tx = poolContract.onExitPool(
        poolId,
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        [ten.mul(10), five.mul(10)],
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(
          ["uint256[]"],
          [[ten.mul(10), five.mul(10)]]
        )
      );
      await expect(tx).to.be.revertedWith("Non Vault caller");
      // blocked swap

      // Tests of invalid formatting
      // Not giving the right pool id on join
      tx = aliasedVault.onJoinPool(
        "0xb6749d30a0b09b310151e2cd2db8f72dd34aab4bbc60cf3e8dbca13b4d9369ad",
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        [ten.mul(10), five.mul(10)],
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(
          ["uint256[]"],
          [[ten.mul(10), five.mul(10)]]
        )
      );
      await expect(tx).to.be.revertedWith("Wrong pool id");
      // Not giving the right pool id on exit
      tx = aliasedVault.onJoinPool(
        "0xb6749d30a0b09b310151e2cd2db8f72dd34aab4bbc60cf3e8dbca13b4d9369ad",
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        [ten.mul(10), five.mul(10)],
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(
          ["uint256[]"],
          [[ten.mul(10), five.mul(10)]]
        )
      );
      await expect(tx).to.be.revertedWith("Wrong pool id");

      // Too many tokens in input array on join
      tx = aliasedVault.onJoinPool(
        poolId,
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        [ten.mul(10), five.mul(10)],
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(
          ["uint256[]"],
          [[ten.mul(10), five.mul(10), ten]]
        )
      );
      await expect(tx).to.be.revertedWith("Invalid format");
      // Too many tokens in input array on join
      tx = aliasedVault.onJoinPool(
        poolId,
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        [ten.mul(10), five.mul(10)],
        0,
        ethers.utils.parseEther("0.1"),
        ethers.utils.defaultAbiCoder.encode(
          ["uint256[]"],
          [[ten.mul(10), five.mul(10), ten]]
        )
      );
      await expect(tx).to.be.revertedWith("Invalid format");
    });
  });

  describe("Pool Factory works", async () => {
    let poolFactory: ConvergentPoolFactory;
    const twentyPercent = ethers.utils.parseEther("0.2");

    before(async () => {
      const testVault = await poolContract.getVault();
      const poolFactoryFactory = new ConvergentPoolFactory__factory(
        accounts[0]
      );
      poolFactory = await poolFactoryFactory.deploy(
        testVault,
        accounts[0].address
      );
    });

    it("Deploys pools", async () => {
      const date = new Date("November 1, 2021 00:00:00");
      const seconds = Math.round(date.getTime() / 1000);

      await poolFactory.create(
        baseAssetContract.address,
        bondAssetContract.address,
        seconds + SECONDS_IN_YEAR / 2,
        SECONDS_IN_YEAR,
        1,
        "fake pool",
        "FP",
        elementSigner.address
      );
    });
    it("Allows changing fees", async () => {
      await poolFactory.setGovFee(twentyPercent);
    });
    it("Blocks invalid fee changes", async () => {
      let tx = poolFactory.setGovFee(ethers.utils.parseEther("0.3").add(1));
      await expect(tx).to.be.revertedWith("New fee higher than 30%");
      tx = poolFactory.connect(accounts[1]).setGovFee(twentyPercent);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
    it("Allows changing governance address", async () => {
      await poolFactory.setGov(accounts[1].address);
      expect(await poolFactory.governance()).to.be.eq(accounts[1].address);
    });
    it("Blocks non owner changes to governance address", async () => {
      const tx = poolFactory.connect(accounts[1]).setGov(fakeAddress);
      await expect(tx).to.be.revertedWith("Sender not owner");
    });
  });

  describe("Pause function", async () => {
    beforeEach(async () => {
      createSnapshot(provider);
    });
    afterEach(async () => {
      restoreSnapshot(provider);
    });
    it("Only lets gov set pause status", async () => {
      await poolContract.setPauser(balancerSigner.address, true);
      const tx = poolContract
        .connect(balancerSigner)
        .setPauser(balancerSigner.address, true);
      await expect(tx).to.be.revertedWith("Sender not Owner");
    });
    it("Only let's pausers pause", async () => {
      await poolContract.pause(true);
      const tx = poolContract.connect(balancerSigner).pause(false);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
    it("Blocks trades and deposits on a paused pool", async () => {
      await poolContract.pause(true);

      let tx = poolContract.onJoinPool(
        "0xb6749d30a0b09b310151e2cd2db8f72dd34aab4bbc60cf3e8dbca13b4d9369ad",
        fakeAddress,
        tokenSigner.address,
        // Pool reserves are [100, 50]
        [0, 0],
        0,
        ethers.utils.parseEther("0.1"),
        "0x"
      );
      await expect(tx).to.be.revertedWith("Paused");
      tx = poolContract.onSwap(
        {
          tokenIn: baseAssetContract.address,
          tokenOut: bondAssetContract.address,
          amount: ethers.utils.parseUnits("100", BASE_DECIMALS),
          kind: inForOutType,
          // Misc data
          poolId:
            "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
          lastChangeBlock: BigNumber.from(0),
          from: fakeAddress,
          to: fakeAddress,
          userData: "0x",
        },
        reserveUnderlying,
        reserveBond
      );
      await expect(tx).to.be.revertedWith("Paused");
    });
  });
});
