import { ConvergentPoolFactory } from "typechain/ConvergentPoolFactory";
import { ConvergentPoolFactory__factory } from "typechain/factories/ConvergentPoolFactory__factory";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { TestVault__factory } from "typechain/factories/TestVault__factory";
import { TestConvergentCurvePool } from "typechain/TestConvergentCurvePool";
import { TestERC20 } from "typechain/TestERC20";
import { TestVault } from "typechain/TestVault";
import { TestConvergentCurvePool__factory } from "typechain/factories/TestConvergentCurvePool__factory";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { ethers, waffle } from "hardhat";
import { SimpleOracle__factory } from "typechain/factories/SimpleOracle__factory";
import { SimpleOracle } from "typechain/SimpleOracle";
import chai, { expect } from "chai";
import { advanceTime } from "./helpers/time";

const { provider } = waffle;

describe("Oracle Tests", async () => {
  const BOND_DECIMALS = 17;
  const BASE_DECIMALS = 6;
  const SECONDS_IN_YEAR = 31536000;
  const inForOutType = 0;
  const outForInType = 1;
  const ORACLE_REBASE_PERIOD = 40 * 60; // 40 minutes

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
  let testVault: TestVault;
  let simpleOracle: SimpleOracle;

  async function getTimestamp() {
    return (await ethers.provider.getBlock("latest")).timestamp;
  }

  before(async () => {
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

    const testVaultDeployer = await new TestVault__factory(tokenSigner);
    testVault = await testVaultDeployer.deploy();

    const curvePoolDeployer = new TestConvergentCurvePool__factory(tokenSigner);
    startTimestamp = await getTimestamp();
    expirationTime = startTimestamp + SECONDS_IN_YEAR;

    poolContract = await curvePoolDeployer.deploy(
      baseAssetContract.address,
      bondAssetContract.address,
      expirationTime,
      SECONDS_IN_YEAR,
      testVault.address,
      ethers.utils.parseEther("0.05"),
      balancerSigner.address,
      `Element USDC - fyUSDC`,
      `USDC-fyUSDC`
    );

    await poolContract.demoUpdate(
      ethers.utils.parseUnits("1000", BOND_DECIMALS),
      ethers.utils.parseUnits("600", BASE_DECIMALS)
    );

    // Deploy Oracle
    const oracleDeployer = await new SimpleOracle__factory(tokenSigner);
    simpleOracle = await oracleDeployer.deploy(
      ORACLE_REBASE_PERIOD,
      poolContract.address
    );
  });

  it("should validate the initialization of the oracle", async () => {
    expect(await simpleOracle.period()).to.be.equal(ORACLE_REBASE_PERIOD);
    expect(await simpleOracle.bond()).to.be.equal(bondAssetContract.address);
    expect(await simpleOracle.underlying()).to.be.equal(
      baseAssetContract.address
    );
    expect(await simpleOracle.pool()).to.be.equal(poolContract.address);
  });

  it("should failed to update as the time period is not passed", async () => {
    const tx = simpleOracle.update();
    await expect(tx).to.be.revertedWith("PeriodNotElapsed()");
  });

  it("should successfully update and consult to get the prices", async () => {
    await advanceTime(provider, 100 * 60); // 31 minutes.
    await poolContract.demoUpdate(
      ethers.utils.parseUnits("1200", BOND_DECIMALS),
      ethers.utils.parseUnits("500", BASE_DECIMALS)
    );
    const oldAvgCumulativeBalancesRatio =
      await simpleOracle.avgCumulativeBalancesRatio();
    const oldBlockTimestampLast = await simpleOracle.blockTimestampLast();
    const currentTimestamp = await getTimestamp();
    await simpleOracle.update();
    expect(await simpleOracle.avgCumulativeBalancesRatio()).to.be.gt(
      oldAvgCumulativeBalancesRatio
    );
    expect(await simpleOracle.blockTimestampLast()).to.be.equal(
      currentTimestamp
    );
    const amountOut = await simpleOracle.consult(
      bondAssetContract.address,
      ethers.utils.parseUnits("200", BOND_DECIMALS)
    );
    expect(amountOut).to.be.gt(1);
  });
});
