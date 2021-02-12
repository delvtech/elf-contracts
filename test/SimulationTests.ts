import {expect} from "chai";
import {ethers} from "hardhat";
import {Contract} from "ethers";

const testTrades = require("./testTrades.json");

describe("YieldPoolErrSim", function() {

  const BOND_DECIMALS = 18;
  const BASE_DECIMALS = 18;

  async function getTimestamp() : Promise<number> {
    return (await ethers.provider.getBlock('latest')).timestamp
  }

  const SECONDS_IN_YEAR = 31536000;
  const fakeAddress = "0x5a0b54d5dc17e0aadc383d2db43b0a0d3e029c4c"
  // This is 10^-9 in 18 point fixed
  const epsilon = ethers.utils.parseUnits("1", 9);
  let pool: Contract;
  let startTimestamp;
  let erc20_base : Contract;
  let erc20_bond : Contract;
  let vault;

  interface TestTrades {
    init: {
      percent_fee: number,
      initial_x_reserves: number,
      initial_y_reserves: number,
      initial_apy: number,
      initial_fyt_price: number,
      max_order_size: number,
      total_supply: number
     },
     trades: TradeData[]
  }

  interface TradeData {
    input: {
      amount_in: number,
      x_reserves: number,
      y_reserves: number,
      time: number,
      token_in: string,
      token_out: string
    },
    output: {
      amount_out: number,
    }
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
      ethers.utils.parseEther(testTrades.init.percent_fee.toString()),
      fakeAddress,
      "YieldBPT",
      "BPT"
    );
    // We now set the total supply
    await (await pool.setLPBalance(fakeAddress, ethers.utils.parseEther(testTrades.init.total_supply.toString()))).wait();
  });

  // This dynamically generated test uses each case in the vector 
  testTrades.trades.forEach(async function(trade: TradeData) {

    let description = "correctly trades " + trade.input.amount_in.toString() +
                       " " + trade.input.token_in + " for " + trade.input.token_out;
    if (trade.input.token_in != "base") {

    it(description, async function() {

        const isBaseIn = trade.input.token_in == "base";
        const tokenAddressIn = isBaseIn? erc20_base.address: erc20_bond.address;
        const tokenAddressOut = isBaseIn? erc20_bond.address: erc20_base.address;
    
        const decimalsIn = isBaseIn? BASE_DECIMALS: BOND_DECIMALS;
        const decimalsOut = isBaseIn? BASE_DECIMALS: BOND_DECIMALS;

        const reserveIn = isBaseIn?  trade.input.x_reserves: trade.input.y_reserves;
        const reserveOut = isBaseIn? trade.input.y_reserves: trade.input.x_reserves;

        console.log("Real time",trade.input.time.toString())
        console.log("Real output", ethers.utils.parseUnits(trade.output.amount_out.toString(), 18));

    
        const value = await pool.callStatic.quoteOutGivenInSimulation(
            {
                tokenIn: tokenAddressIn,
                tokenOut: tokenAddressOut,
                amountIn: ethers.utils.parseUnits(trade.input.amount_in.toString(), decimalsIn),
                // Misc data
                poolId: "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
                from:  fakeAddress,
                to:  fakeAddress,
                userData: "0x"
            },
            ethers.utils.parseUnits(reserveIn.toString(), decimalsIn),
            ethers.utils.parseUnits(reserveOut.toString(), decimalsOut),
            ethers.utils.parseUnits(trade.input.time.toString(), 18),
            ethers.utils.parseUnits(trade.output.amount_out.toString(), 18)
        );
        
        console.log(value);
        expect(value.lt(epsilon)).to.be.eq(true);
    });
  }
  });
});