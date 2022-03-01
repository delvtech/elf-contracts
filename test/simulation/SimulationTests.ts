import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, BigNumber } from "ethers";
import { impersonate, stopImpersonating } from "../helpers/impersonate";
import { TestConvergentCurvePool } from "typechain/TestConvergentCurvePool";
import testTrades from "./testTrades.json";

// This simulation loads the data from ./testTrades.json and makes sure that
// our quotes are with-in 10^-8 (assuming BASE and BOND are both 18 point fixed)of the quotes from the python script
describe("ConvergentCurvePoolErrSim", function () {
  const inForOutType = 0;
  const outForInType = 1;

  async function getTimestamp(): Promise<number> {
    return (await ethers.provider.getBlock("latest")).timestamp;
  }

  const SECONDS_IN_YEAR = 31536000;
  const fakeAddress = "0x5a0b54d5dc17e0aadc383d2db43b0a0d3e029c4c";

  let DECIMALS: number;
  let EPSILON: number;
  let epsilon: BigNumber;
  let pool: TestConvergentCurvePool;
  let startTimestamp: number;
  let erc20_base: Contract;
  let erc20_bond: Contract;
  let vault: Contract;

  interface TradeData {
    input: {
      amount_in: number;
      x_reserves: number;
      y_reserves: number;
      total_supply: number;
      time: number;
      token_in: string;
      token_out: string;
      direction: string;
    };
    output: {
      amount_out: number;
    };
  }

  before(async function () {
    DECIMALS = (testTrades as any).init.decimals;
    EPSILON = Math.max(10, 18 - DECIMALS + 1);
    epsilon = ethers.utils.parseUnits("1", EPSILON);
    startTimestamp = await getTimestamp();

    const ERC20 = await ethers.getContractFactory("TestERC20");
    erc20_bond = await ERC20.deploy("Bond", "EL1Y", DECIMALS);
    erc20_base = await ERC20.deploy("Stablecoin", "USDC", DECIMALS);

    const Vault = await ethers.getContractFactory("TestVault");
    vault = await Vault.deploy();
    const Pool = await ethers.getContractFactory("TestConvergentCurvePool");
    pool = (await Pool.deploy(
      erc20_base.address.toString(),
      erc20_bond.address.toString(),
      startTimestamp + SECONDS_IN_YEAR,
      SECONDS_IN_YEAR,
      vault.address.toString(),
      ethers.utils.parseEther((testTrades as any).init.percent_fee.toString()),
      fakeAddress,
      "ConvergentCurveBPT",
      "BPT"
    )) as TestConvergentCurvePool;
    impersonate(vault.address);
  });

  after(async () => {
    stopImpersonating(vault.address);
  });

  // This dynamically generated test uses each case in the vector
  (testTrades as any).trades.forEach(function (trade: TradeData) {
    const description = `correctly trades ${trade.input.amount_in.toString()} ${
      trade.input.token_in
    } for ${trade.input.token_out}. direction: ${trade.input.direction}`;

    it(description, function (done) {
      const isBaseIn = trade.input.token_in === "base";
      const tokenAddressIn = isBaseIn ? erc20_base.address : erc20_bond.address;
      const tokenAddressOut = isBaseIn
        ? erc20_bond.address
        : erc20_base.address;

      const reserveIn = isBaseIn
        ? trade.input.x_reserves
        : trade.input.y_reserves;
      const reserveOut = isBaseIn
        ? trade.input.y_reserves
        : trade.input.x_reserves;

      const kind = trade.input.direction == "in" ? outForInType : inForOutType;
      pool
        .connect(vault.address)
        .callStatic.swapSimulation(
          {
            tokenIn: tokenAddressIn,
            tokenOut: tokenAddressOut,
            amount: ethers.utils.parseUnits(
              trade.input.amount_in.toString(),
              DECIMALS
            ),
            kind: kind,
            // Misc data
            poolId:
              "0xf4cc12715b126dabd383d98cfad15b0b6c3814ad57c5b9e22d941b5fcd3e4e43",
            lastChangeBlock: BigNumber.from(0),
            from: fakeAddress,
            to: fakeAddress,
            userData: "0x",
          },
          ethers.utils.parseUnits(reserveIn.toString(), DECIMALS),
          ethers.utils.parseUnits(reserveOut.toString(), DECIMALS),
          ethers.utils.parseUnits(trade.input.time.toString(), 18),
          ethers.utils.parseUnits(trade.output.amount_out.toString(), DECIMALS),
          ethers.utils.parseEther(trade.input.total_supply.toString())
        )
        .then(check);
      // We use a closure after the promise to retain access to the mocha done
      // call
      function check(value: BigNumber) {
        try {
          // We try the expectation
          expect(value.lt(epsilon)).to.be.eq(true);
          // If it passes we are done
          done();
        } catch (e) {
          // If it fails we return an error to mocha
          done(e);
        }
      }
    });
  });
});
