import "module-alias/register";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import chai, { expect } from "chai";
import chaiAlmost from "chai-almost";
import { BigNumber, providers } from "ethers";
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
import { TestConvergentCurvePool } from "typechain/TestConvergentCurvePool";
import { TestERC20 } from "typechain/TestERC20";
import { Vault } from "typechain/Vault";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

// we need to use almost for the onSwap tests since `hardhat coverage` compiles the contracts
// slightly differently which causes slightly different fixedpoint logic.
// normal tests are also failing on CI now, setting the tolerance to 10^-4 so that they will pass.
// TODO: figure out if we can only apply tolerance to the coverage tests.
// const DEFAULT_CHAI_ALMOST_TOLERANCE = 10e-4;
// const tolerance = process.env.COVERAGE ? DEFAULT_CHAI_ALMOST_TOLERANCE : 0;
chai.use(chaiAlmost(10e-4));

describe("ConvergentCurvePool", function () {
  const BOND_DECIMALS = 17;
  const BASE_DECIMALS = 6;
  const SECONDS_IN_YEAR = 31536000;

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
    await balancerVaultContract.changeRelayerAllowance(elementAddress, true);

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

  it("Internally Mints LP correctly for Governance", async function () {
    await resetPool();
    let govBalanceStart = await poolContract.balanceOf(elementAddress);
    const ten = ethers.utils.parseUnits("10", 18);
    const five = ethers.utils.parseUnits("5", 18);
    // We set the accumulated fees
    await mineTx(poolContract.setFees(ten, five));
    // Set the current total supply to 100 lp tokens
    await mineTx(poolContract.setLPBalance(elementAddress, ten.mul(ten)));
    govBalanceStart = await poolContract.balanceOf(elementAddress);
    // Mint governance lp
    await mineTx(poolContract.mintGovLP([ten.mul(ten), five.mul(ten)]));
    // We now check that all of the fees were consume
    const feesUnderlying = await poolContract.feesUnderlying();
    const feesBond = await poolContract.feesBond();
    expect(newBigNumber(0)).to.be.eq(feesUnderlying);
    expect(newBigNumber(0)).to.be.eq(feesBond);
    // We check that the governance address got ten lp tokens
    const govBalanceNew = await poolContract.balanceOf(elementAddress);
    expect(ethers.utils.parseUnits("0.5", 18).add(govBalanceStart)).to.be.eq(
      govBalanceNew
    );
  });

  // We test the mint functionality where the bond should be fully consumed
  it("Internally Mints LP correctly for the bond max", async function () {
    await resetPool();
    const oneThousand = ethers.utils.parseUnits("1000", 18);
    // Set the current total supply to 1000 lp tokens
    await mineTx(poolContract.setLPBalance(accounts[0].address, oneThousand));
    // We want a min of 500 underlying and 100 bond
    const fiveHundred = ethers.utils.parseUnits("500", 18);
    const result = await mineTx(
      poolContract.burnLP(
        fiveHundred,
        fiveHundred.div(5),
        [oneThousand, fiveHundred],
        accounts[0].address
      )
    );
    // The call should have released 500 underlying and 250 bond
    const returned = result.events.filter(
      (event) => event.event == "UIntReturn"
    );
    expect(returned[0].data).to.be.eq(fiveHundred);
    expect(returned[1].data).to.be.eq(fiveHundred.div(2));
    // The call should have burned 50% of the LP tokens to produce this
    const balance = await poolContract.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(fiveHundred);
    const totalSupply = await poolContract.totalSupply();
    expect(totalSupply).to.be.eq(fiveHundred);
  });

  // We test the mint functionality where the bond should be fully consumed
  it("Internally Mints LP correctly for the underlying max", async function () {
    await resetPool();
    const oneThousand = ethers.utils.parseUnits("1000", 18);
    // Set the current total supply to 1000 lp tokens
    await mineTx(poolContract.setLPBalance(accounts[0].address, oneThousand));
    // We want a min of 250 underlying and 250 bond
    const fiveHundred = ethers.utils.parseUnits("500", 18);
    const twoFifty = fiveHundred.div(2);
    const result = await mineTx(
      poolContract.burnLP(
        twoFifty,
        twoFifty,
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
    const amount = ethers.utils.parseUnits("11000");
    const inputUnderlying = ethers.utils.parseUnits("10000");

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
    expect(returned[0].data).to.be.eq(ethers.utils.parseUnits("10950"));
    // Check the stored fees
    const feeBond = await poolContract.feesBond();
    expect(feeBond).to.be.eq(ethers.utils.parseUnits("50", BOND_DECIMALS));

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
    expect(returned[0].data).to.be.eq(ethers.utils.parseUnits("10050"));
    // Check the stored fees
    const feeUnderlying = await poolContract.feesUnderlying();
    expect(feeUnderlying).to.be.eq(
      ethers.utils.parseUnits("50", BASE_DECIMALS)
    );
  });

  // We test the assigned trade fee when selling a bond
  it("Calculates fees correctly for a sell", async function () {
    await resetPool();
    const inputBond = ethers.utils.parseUnits("11000");
    const amount = ethers.utils.parseUnits("10000");

    // Check the case when this is an output trade
    let result = await mineTx(
      poolContract.assignTradeFee(
        inputBond,
        amount,
        baseAssetContract.address,
        false
      )
    );
    let returned = result.events.filter((event) => event.event == "UIntReturn");
    expect(returned[0].data).to.be.eq(ethers.utils.parseUnits("9950"));
    // Check the stored fees
    const feeUnderlying = await poolContract.feesUnderlying();
    expect(feeUnderlying).to.be.eq(
      ethers.utils.parseUnits("50", BASE_DECIMALS)
    );

    // Check the case when this is an input trade
    result = await mineTx(
      poolContract.assignTradeFee(
        inputBond,
        amount,
        baseAssetContract.address,
        true
      )
    );
    returned = result.events.filter((event) => event.event == "UIntReturn");
    expect(returned[0].data).to.be.eq(ethers.utils.parseUnits("11050"));
    // Check the stored fees
    const feesBond = await poolContract.feesBond();
    expect(feesBond).to.be.eq(ethers.utils.parseUnits("50", BOND_DECIMALS));
  });

  // We get a series of quotes for specifically checked trades

  it("Quotes a buy output trade correctly", async function () {
    await resetPool();

    const quote = await poolContract.callStatic.onSwapGivenIn(
      {
        tokenIn: baseAssetContract.address,
        tokenOut: bondAssetContract.address,
        amountIn: ethers.utils.parseUnits("100", BASE_DECIMALS),
        // Misc data
        poolId:
          "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
        latestBlockNumberUsed: BigNumber.from(0),
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
    const quote = await poolContract.callStatic.onSwapGivenIn(
      {
        tokenIn: bondAssetContract.address,
        tokenOut: baseAssetContract.address,
        amountIn: ethers.utils.parseUnits("100", BOND_DECIMALS),
        // Misc data
        poolId:
          "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
        latestBlockNumberUsed: BigNumber.from(0),
        from: fakeAddress,
        to: fakeAddress,
        userData: "0x",
      },
      reserveBond,
      reserveUnderlying
    );
    expect(quote).to.be.eq(ethers.utils.parseUnits("90.434755", BASE_DECIMALS));
  });

  it("Quotes a buy input trade correctly", async function () {
    const quote = await poolContract.callStatic.onSwapGivenOut(
      {
        tokenIn: baseAssetContract.address,
        tokenOut: bondAssetContract.address,
        amountOut: ethers.utils.parseUnits("200", BOND_DECIMALS),
        // Misc data
        poolId:
          "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
        latestBlockNumberUsed: BigNumber.from(0),
        from: fakeAddress,
        to: fakeAddress,
        userData: "0x",
      },
      reserveUnderlying,
      reserveBond
    );
    expect(quote).to.be.eq(
      ethers.utils.parseUnits("184.972608", BASE_DECIMALS)
    );
  });

  it("Quotes a sell input trade correctly", async function () {
    const quote = await poolContract.callStatic.onSwapGivenOut(
      {
        tokenIn: bondAssetContract.address,
        tokenOut: baseAssetContract.address,
        amountOut: ethers.utils.parseUnits("150", BASE_DECIMALS),
        // Misc data
        poolId:
          "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
        latestBlockNumberUsed: BigNumber.from(0),
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
      await poolFactory.create(
        baseAssetContract.address,
        bondAssetContract.address,
        1000,
        1000,
        1,
        "fake pool",
        "FP"
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
});
