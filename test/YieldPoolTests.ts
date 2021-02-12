import {expect} from "chai";
import {ethers, ethers.providers, network} from "hardhat";
import {Contract, BigNumber, providers} from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { LogDescription } from "ethers/lib/utils";

describe("YieldPool", function() {

  const BOND_DECIMALS = 17;
  const BASE_DECIMALS = 6;
  const SECONDS_IN_YEAR = 31536000;
  const fakeAddress = "0x5a0b54d5dc17e0aadc383d2db43b0a0d3e029c4c"
  let accounts: SignerWithAddress[];
  let pool: Contract;
  let startTimestamp: number;
  let erc20_base: Contract;
  let erc20_bond: Contract;
  let vault: Contract;

  async function getTimestamp() {
    return (await ethers.provider.getBlock('latest')).timestamp
  }

  // An interface to allow us to access the ethers log return
  interface LogData {
    event: string,
    data: any
  }

  // A partially extended interface for the post mining transaction receipt
  interface PostExecutionTransactionReceipt extends providers.TransactionReceipt {
    events: LogData[]
  };

  async function mineTx(tx: Promise<ethers.providers.TransactionResponse>): Promise<PostExecutionTransactionReceipt> {
    return (await tx).wait() as Promise<PostExecutionTransactionReceipt>;
  }

  function newBigNumber(data: number): BigNumber {
    const cast = new (BigNumber.from as any)(data);
    return cast;
  }

  async function resetPool() {
    const Pool = await ethers.getContractFactory("YieldPoolTest");
    pool = await Pool.deploy(
      erc20_base.address.toString(),
      erc20_bond.address.toString(),
      startTimestamp + SECONDS_IN_YEAR,
      SECONDS_IN_YEAR,
      vault.address.toString(),
      ethers.utils.parseEther("0.05"),
      fakeAddress,
      "YieldBPT",
      "BPT"
    );
  }
  
  before(async function() {
    startTimestamp = await getTimestamp();

    const ERC20 = await ethers.getContractFactory("TestERC20");
    erc20_bond = await ERC20.deploy("Bond", "EL1Y", BOND_DECIMALS);
    erc20_base = await ERC20.deploy("Stablecoin", "USDC", BASE_DECIMALS);

    const Vault = await ethers.getContractFactory("TestVault");
    vault = await Vault.deploy();

    const Pool = await ethers.getContractFactory("YieldPoolTest");
    pool = await Pool.deploy(
      erc20_base.address.toString(),
      erc20_bond.address.toString(),
      startTimestamp + SECONDS_IN_YEAR,
      SECONDS_IN_YEAR,
      vault.address.toString(),
      ethers.utils.parseEther("0.05"),
      fakeAddress,
      "YieldBPT",
      "BPT"
    );
    
     accounts = await ethers.getSigners();
  });

  it("Normalize tokens correctly", async function() {
    const one = ethers.utils.parseUnits("1", 18);
    // We check that the same decimals is a no opp
    const no_opp = await pool.normalize(one, 18, 18);
    expect(no_opp).to.be.eq(one);
    // We check that it reduces decimals correctly
    const bp = await pool.normalize(one, 18, 14);
    expect(bp).to.be.eq(ethers.utils.parseUnits("1", 14));
    // We check that it increases decimals  correctly
    const x100 = await pool.normalize(one, 18, 20);
    expect(x100).to.be.eq(ethers.utils.parseUnits("1", 20));
  });

  function getRandomInt(max: number) {
    return Math.floor(Math.random() * Math.floor(max));
  }

  it("Converts token units to decimal units", async function() {
    // Check that a random bond unit is correctly decimal encoded
    let tokenAmount = getRandomInt(1000);
    let normalized = await pool.tokenToFixed(ethers.utils.parseUnits(tokenAmount.toString(), BOND_DECIMALS), erc20_bond.address);
    expect(normalized).to.be.eq(ethers.utils.parseUnits(tokenAmount.toString(), 18));
    // Check that the underlying token normalizes correctly
    normalized = await pool.tokenToFixed(ethers.utils.parseUnits(tokenAmount.toString(), BASE_DECIMALS), erc20_base.address);
    expect(normalized).to.be.eq(ethers.utils.parseUnits(tokenAmount.toString(), 18));
  });

  it("Converts token units to decimal units", async function() {
    // Check that a random bond unit is correctly decimal encoded
    let tokenAmount = getRandomInt(1000);
    let normalized = await pool.tokenToFixed(ethers.utils.parseUnits(tokenAmount.toString(), BOND_DECIMALS), erc20_bond.address);
    expect(normalized).to.be.eq(ethers.utils.parseUnits(tokenAmount.toString(), 18));
    // Check that the underlying token normalizes correctly
    normalized = await pool.tokenToFixed(ethers.utils.parseUnits(tokenAmount.toString(), BASE_DECIMALS), erc20_base.address);
    expect(normalized).to.be.eq(ethers.utils.parseUnits(tokenAmount.toString(), 18));
  });

  it("Converts token units to decimal units", async function() {
    // Check that a random bond unit is correctly decimal encoded
    let randAmount = getRandomInt(1000);
    let normalized = ethers.utils.parseUnits(randAmount.toString(), 18)
    let tokenAmount = await pool.fixedToToken(normalized, erc20_bond.address);
    expect(tokenAmount).to.be.eq(ethers.utils.parseUnits(randAmount.toString(), BOND_DECIMALS));
    // Check that the underlying token normalizes correctly
    tokenAmount = await pool.fixedToToken(normalized, erc20_base.address);
    expect(tokenAmount).to.be.eq(ethers.utils.parseUnits(randAmount.toString(), BASE_DECIMALS));
  });

  it("Returns the correct fractional time", async function() {
    // We set the next block's time to be the start time + 1/2 * SECONDS_IN_YEAR
    await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp + (SECONDS_IN_YEAR/2)]);
    await network.provider.send("evm_mine")
    // We now call the function which returns 1 - t, which should be 0.5
    let exponent = await pool.getYieldExponent();
    expect(exponent).to.be.eq(ethers.utils.parseUnits("0.5", 18));
  });

  it("Mints LP in empty pool correctly", async function() {
    // We use the mintLP function in tes
    const oneThousand = ethers.utils.parseUnits("1000", 18);
    const result = await mineTx(pool.mintLP(oneThousand,
      oneThousand,
      [0,0],
      accounts[0].address));
    // Check that it returns the right data using the event hack
    const returned = result.events.filter(event =>  event.event == "uintReturn");
    expect(returned[0].data).to.be.eq(oneThousand);
    expect(returned[1].data).to.be.eq(newBigNumber(0));
    // Check the LP balance
    const balance = await pool.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(oneThousand);
  });
  
  // We test the mint functionality where the underlying should be fully
  // consumed
  it("Internally Mints LP correctly for underlying max", async function() {
    await resetPool();
    const oneThousand = ethers.utils.parseUnits("1000", 18);
    // Set the current total supply to 1000 lp tokens
    await mineTx(pool.setLPBalance(accounts[1].address, oneThousand));
    // We use the mintLP function in tes
    const fiveHundred = ethers.utils.parseUnits("500", 18);
    const result = await mineTx(pool.mintLP(oneThousand,
      oneThousand,
      [oneThousand, fiveHundred],
      accounts[0].address));
    // Check that it returns the right data using the event hack
    const returned = result.events.filter(event =>  event.event == "uintReturn");
    expect(returned[0].data).to.be.eq(oneThousand);
    expect(returned[1].data).to.be.eq(fiveHundred);
    // Check the LP balance
    const balance = await pool.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(oneThousand);
    const totalSupply = await pool.totalSupply();
    expect(totalSupply).to.be.eq(ethers.utils.parseUnits("2000", 18));
  });

  // We test the mint functionality where the bond should be fully consumed
  it("Internally Mints LP correctly for the bond max", async function() {
    await resetPool();
    const twoThousand = ethers.utils.parseUnits("2000", 18);
    const oneThousand = twoThousand.div(2);
    // Set the current total supply to 1000 lp tokens
    await mineTx(pool.setLPBalance(accounts[1].address, oneThousand));
    // We use the mintLP function in tes
    const fiveHundred = ethers.utils.parseUnits("500", 18);
    const eightHundred = ethers.utils.parseUnits("800", 18);
    const result = await mineTx(pool.mintLP(twoThousand,
      eightHundred,
      [oneThousand, fiveHundred],
      accounts[0].address));
    // Check that it returns the right data using the event hack
    const returned = result.events.filter(event =>  event.event == "uintReturn");
    const sixteenHundred = ethers.utils.parseUnits("1600", 18);
    expect(returned[0].data).to.be.eq(sixteenHundred);
    expect(returned[1].data).to.be.eq(eightHundred);
    // Check the LP balance
    const balance = await pool.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(sixteenHundred);
    const totalSupply = await pool.totalSupply();
    expect(totalSupply).to.be.eq(oneThousand.add(sixteenHundred));
  });

  it("Internally Mints LP correctly for Governance", async function() {
    await resetPool();
    const ten = ethers.utils.parseUnits("10", 18);
    const five = ethers.utils.parseUnits("5", 18);
    // We set the accumulated fees
    await mineTx(pool.setFees(ten, five));
    // Set the current total supply to 100 lp tokens
    await mineTx(pool.setLPBalance(accounts[1].address, ten.mul(ten)));
    // Mint governance lp
    await mineTx(pool.mintGovLP([ten.mul(ten), five.mul(ten)]));
    // We now check that all of the fees were consume
    let feesUnderlying = await pool.feesUnderlying();
    let feesBond = await pool.feesBond();
    expect(newBigNumber(0)).to.be.eq(feesUnderlying);
    expect(newBigNumber(0)).to.be.eq(feesBond);
    // We check that the governance address got ten lp tokens
    let govBalance = await pool.balanceOf(fakeAddress);
    expect(ethers.utils.parseUnits("0.5", 18)).to.be.eq(govBalance);
  });

    // We test the mint functionality where the bond should be fully consumed
  it("Internally Mints LP correctly for the bond max", async function() {
    await resetPool();
    const oneThousand = ethers.utils.parseUnits("1000", 18);
    // Set the current total supply to 1000 lp tokens
    await mineTx(pool.setLPBalance(accounts[0].address, oneThousand));
    // We want a min of 500 underlying and 100 bond
    const fiveHundred = ethers.utils.parseUnits("500", 18);
    const result = await mineTx(pool.burnLP(fiveHundred,
      fiveHundred.div(5),
      [oneThousand, fiveHundred],
      accounts[0].address));
    // The call should have released 500 underlying and 250 bond
    const returned = result.events.filter(event =>  event.event == "uintReturn");
    expect(returned[0].data).to.be.eq(fiveHundred);
    expect(returned[1].data).to.be.eq(fiveHundred.div(2));
    // The call should have burned 50% of the LP tokens to produce this
    const balance = await pool.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(fiveHundred);
    const totalSupply = await pool.totalSupply();
    expect(totalSupply).to.be.eq(fiveHundred);
  });

  // We test the mint functionality where the bond should be fully consumed
  it("Internally Mints LP correctly for the underlying max", async function() {
    await resetPool();
    const oneThousand = ethers.utils.parseUnits("1000", 18);
    // Set the current total supply to 1000 lp tokens
    await mineTx(pool.setLPBalance(accounts[0].address, oneThousand));
    // We want a min of 250 underlying and 250 bond
    const fiveHundred = ethers.utils.parseUnits("500", 18);
    const twoFifty = fiveHundred.div(2);
    const result = await mineTx(pool.burnLP(twoFifty,
      twoFifty,
      [oneThousand, fiveHundred],
      accounts[0].address));
    // The call should have released 500 underlying and 250 bond
    const returned = result.events.filter(event =>  event.event == "uintReturn");
    expect(returned[0].data).to.be.eq(fiveHundred);
    expect(returned[1].data).to.be.eq(twoFifty);
    // The call should have burned 50% of the LP tokens to produce this
    const balance = await pool.balanceOf(accounts[0].address);
    expect(balance).to.be.eq(fiveHundred);
    const totalSupply = await pool.totalSupply();
    expect(totalSupply).to.be.eq(fiveHundred);
  });

  // We test the assigned trade fee when buying a bond
  it("Calculates fees correctly for a buy", async function() {
    await resetPool();
    const amount = ethers.utils.parseUnits("11000", 18);
    const inputUnderlying = ethers.utils.parseUnits("10000", 18);

    // Check the case when this is an output trade
    let result = await mineTx(pool.assignTradeFee(inputUnderlying, amount, erc20_bond.address, false));   
    let returned = result.events.filter(event => event.event == "uintReturn");
    expect(returned[0].data).to.be.eq(ethers.utils.parseUnits("10950", 18));
    // Check the stored fees
    const feeBond = await pool.feesBond();
    expect(feeBond).to.be.eq(ethers.utils.parseUnits("50", BOND_DECIMALS));

    // Check the case when this is an input trade
    result = await mineTx(pool.assignTradeFee(inputUnderlying, amount, erc20_bond.address, true));   
    returned = result.events.filter(event => event.event == "uintReturn");
    expect(returned[0].data).to.be.eq(ethers.utils.parseUnits("10050", 18));
    // Check the stored fees
    const feeUnderlying = await pool.feesUnderlying();
    expect(feeUnderlying).to.be.eq(ethers.utils.parseUnits("50", BASE_DECIMALS));
  });

    // We test the assigned trade fee when selling a bond
    it("Calculates fees correctly for a sell", async function() {
      await resetPool();
      const inputBond = ethers.utils.parseUnits("11000", 18);
      const amount = ethers.utils.parseUnits("10000", 18);
  
      // Check the case when this is an output trade
      let result = await mineTx(pool.assignTradeFee(inputBond, amount, erc20_base.address, false));   
      let returned = result.events.filter(event => event.event == "uintReturn");
      expect(returned[0].data).to.be.eq(ethers.utils.parseUnits("9950", 18));
      // Check the stored fees
      const feeUnderlying = await pool.feesUnderlying();
      expect(feeUnderlying).to.be.eq(ethers.utils.parseUnits("50", BASE_DECIMALS));
  
      // Check the case when this is an input trade
      result = await mineTx(pool.assignTradeFee(inputBond, amount, erc20_base.address, true));   
      returned = result.events.filter(event => event.event == "uintReturn");
      expect(returned[0].data).to.be.eq(ethers.utils.parseUnits("11050", 18));
      // Check the stored fees
      const feesBond = await pool.feesBond();
      expect(feesBond).to.be.eq(ethers.utils.parseUnits("50", BOND_DECIMALS));
    });

      // We get a series of quotes for specifically checked trades

  it("Quotes a buy output trade correctly", async function() {
    await resetPool();
    const reserveBond = ethers.utils.parseUnits("12000", BOND_DECIMALS);
    const reserveUnderlying = ethers.utils.parseUnits("10000",BASE_DECIMALS);

    let quote = await pool.callStatic.quoteOutGivenIn(
        {
            tokenIn: erc20_base.address,
            tokenOut: erc20_bond.address,
            amountIn: ethers.utils.parseUnits("100",BASE_DECIMALS),
            // Misc data
            poolId: "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
            from: fakeAddress,
            to: fakeAddress,
            userData: "0x"
        },
        reserveUnderlying,
        reserveBond
    );
    expect(quote).to.be.eq(ethers.utils.parseUnits("108.57207702019185228", BOND_DECIMALS));
  });

  it("Quotes a sell output trade correctly", async function() {
    const reserveBond = ethers.utils.parseUnits("12000", BOND_DECIMALS);
    const reserveUnderlying = ethers.utils.parseUnits("10000",BASE_DECIMALS);

    let quote = await pool.callStatic.quoteOutGivenIn(
        {
            tokenIn: erc20_bond.address,
            tokenOut: erc20_base.address,
            amountIn: ethers.utils.parseUnits("100", BOND_DECIMALS),
            // Misc data
            poolId: "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
            from: fakeAddress,
            to: fakeAddress,
            userData: "0x"
        },
        reserveBond,
        reserveUnderlying
    );
    expect(quote).to.be.eq(ethers.utils.parseUnits("90.434755", BASE_DECIMALS));
  });

  it("Quotes a buy input trade correctly", async function() {
    const reserveBond = ethers.utils.parseUnits("12000", BOND_DECIMALS);
    const reserveUnderlying = ethers.utils.parseUnits("10000", BASE_DECIMALS);

    let quote = await pool.callStatic.quoteInGivenOut(
        {
            tokenIn: erc20_base.address,
            tokenOut: erc20_bond.address,
            amountOut: ethers.utils.parseUnits("200", BOND_DECIMALS),
            // Misc data
            poolId: "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
            from:  fakeAddress,
            to:  fakeAddress,
            userData: "0x"
        },
        reserveUnderlying,
        reserveBond
    );
    expect(quote).to.be.eq(ethers.utils.parseUnits("184.972607", BASE_DECIMALS));
  });

  it("Quotes a sell input trade correctly", async function() {
    const reserveBond = ethers.utils.parseUnits("12000", BOND_DECIMALS);
    const reserveUnderlying = ethers.utils.parseUnits("10000", BASE_DECIMALS);

    let quote = await pool.callStatic.quoteInGivenOut(
        {
            tokenIn: erc20_bond.address,
            tokenOut: erc20_base.address,
            amountOut: ethers.utils.parseUnits("150", BASE_DECIMALS),
            // Misc data
            poolId: "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
            from:  fakeAddress,
            to:  fakeAddress,
            userData: "0x"
        },
        reserveBond,
        reserveUnderlying
    );
    expect(quote).to.be.eq(ethers.utils.parseUnits("166.27957189013109567", BOND_DECIMALS));
  });
});