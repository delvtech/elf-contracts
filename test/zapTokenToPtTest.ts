import { Signer } from "ethers";
import { formatEther } from "ethers/lib/utils";
import { ethers, waffle } from "hardhat";
import { ZapTokenToPt } from "typechain/ZapTokenToPt";
import { ONE_ETH, ZERO, _ETH_CONSTANT } from "./helpers/constants";
import {
  deploy,
  ZapCurveTokenFixture,
  ZapCurveTokenFixtureConstructorFn,
} from "./helpers/deployZapCurveTokenToPt";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

describe.only("zapTokenToPt", () => {
  let users: { user: Signer; address: string }[];

  let zapTokenToPt: ZapTokenToPt;
  let constructZapFixture: ZapCurveTokenFixtureConstructorFn;

  before(async () => {
    await createSnapshot(provider);

    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return { user, address: "" };
    });

    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    ({ zapTokenToPt, constructZapFixture } = await deploy(users[1].address));
  });

  after(async () => {
    // revert back to initial state after all tests pass
    await restoreSnapshot(provider);
  });
  beforeEach(async () => {
    await createSnapshot(provider);
  });
  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("ETH:STETH -> ePyvcrvSTETH", () => {
    let constructZapStructs: ZapCurveTokenFixture<"ePyvcrvSTETH">["constructZapStructs"];
    let tokens: ZapCurveTokenFixture<"ePyvcrvSTETH">["tokens"];
    let stealFromWhale: ZapCurveTokenFixture<"ePyvcrvSTETH">["stealFromWhale"];

    before(async () => {
      ({ constructZapStructs, tokens, stealFromWhale } =
        await constructZapFixture({
          zapTrie: {
            ePyvcrvSTETH: {
              stCRV: ["ETH", "stETH"],
            },
          },
          balancerPoolId:
            "0xb03c6b351a283bc1cd26b9cf6d7b0c4556013bdb0002000000000000000000ab",
          addresses: {
            ETH: _ETH_CONSTANT,
            stETH: "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",
            stCRV: "0x06325440D014e39736583c165C2963BA99fAf14E",
            ePyvcrvSTETH: "0x2361102893CCabFb543bc55AC4cC8d6d0824A67E",
          },
          pools: {
            stCRV: "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022",
          },
          whales: {
            stETH: "0x06920C9fC643De77B99cB7670A944AD31eaAA260",
          },
        }));
    });

    it("should swap ETH for eP:yvcrvSTETH", async () => {
      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          ETH: ONE_ETH,
          stETH: ZERO,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps, {
          value: ethers.utils.parseEther("1"),
        });

      const ptBalance = await tokens.ePyvcrvSTETH.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });

    it("should swap stETH for eP:yvcrvSTETH", async () => {
      await stealFromWhale({
        recipient: users[1].address,
        token: "stETH",
        amount: ONE_ETH,
      });

      await tokens.stETH
        .connect(users[1].user)
        .approve(zapTokenToPt.address, ONE_ETH);

      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          ETH: ZERO,
          stETH: ONE_ETH,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps);

      const ptBalance = await tokens.ePyvcrvSTETH.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });

    it("should swap stETH and ETH for eP:yvcrvSTETH", async () => {
      await stealFromWhale({
        recipient: users[1].address,
        token: "stETH",
        amount: ONE_ETH,
      });

      await tokens.stETH
        .connect(users[1].user)
        .approve(zapTokenToPt.address, ONE_ETH);

      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          ETH: ONE_ETH,
          stETH: ONE_ETH,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps, { value: ONE_ETH });

      const ptBalance = await tokens.ePyvcrvSTETH.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });
  });

  describe("USDT:WBTC:WETH -> ePyvcrv3crypto", () => {
    let constructZapStructs: ZapCurveTokenFixture<"ePyvcrv3crypto">["constructZapStructs"];
    let tokens: ZapCurveTokenFixture<"ePyvcrv3crypto">["tokens"];
    let stealFromWhale: ZapCurveTokenFixture<"ePyvcrv3crypto">["stealFromWhale"];

    before(async () => {
      ({ constructZapStructs, tokens, stealFromWhale } =
        await constructZapFixture({
          zapTrie: {
            ePyvcrv3crypto: {
              crvTriCrypto: ["USDT", "WBTC", "WETH"],
            },
          },
          balancerPoolId:
            "0x6dd0f7c8f4793ed2531c0df4fea8633a21fdcff40002000000000000000000b7",
          addresses: {
            USDT: "0xdac17f958d2ee523a2206206994597c13d831ec7",
            WBTC: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
            WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
            crvTriCrypto: "0xc4AD29ba4B3c580e6D59105FFf484999997675Ff",
            ePyvcrv3crypto: "0x285328906D0D33cb757c1E471F5e2176683247c2",
          },
          pools: {
            crvTriCrypto: "0xD51a44d3FaE010294C616388b506AcdA1bfAAE46",
          },
          whales: {
            USDT: "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
            WBTC: "0xE3DD3914aB28bB552d41B8dFE607355DE4c37A51",
            WETH: "0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3",
          },
        }));
    });

    it("should swap WBTC for ePyvcrv3crypto", async () => {
      const amountWBTC = ethers.utils.parseUnits("1", 8);

      await stealFromWhale({
        recipient: users[1].address,
        token: "WBTC",
        amount: amountWBTC,
      });

      await tokens.WBTC.connect(users[1].user).approve(
        zapTokenToPt.address,
        amountWBTC
      );

      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          USDT: ZERO,
          WBTC: amountWBTC,
          WETH: ZERO,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps);

      const ptBalance = await tokens.ePyvcrv3crypto.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });

    it("should swap USDT for ePyvcrv3crypto", async () => {
      const amountUSDT = ethers.utils.parseUnits("60000", 6);

      await stealFromWhale({
        recipient: users[1].address,
        token: "USDT",
        amount: amountUSDT,
      });

      await tokens.USDT.connect(users[1].user).approve(
        zapTokenToPt.address,
        amountUSDT
      );

      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          USDT: amountUSDT,
          WBTC: ZERO,
          WETH: ZERO,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps);

      const ptBalance = await tokens.ePyvcrv3crypto.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });

    it("should swap WETH for ePyvcrv3crypto", async () => {
      const amountWETH = ethers.utils.parseUnits("15", 18);

      await stealFromWhale({
        recipient: users[1].address,
        token: "WETH",
        amount: amountWETH,
      });

      await tokens.WETH.connect(users[1].user).approve(
        zapTokenToPt.address,
        amountWETH
      );

      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          USDT: ZERO,
          WBTC: ZERO,
          WETH: amountWETH,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps);

      const ptBalance = await tokens.ePyvcrv3crypto.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });

    it("should swap WBTC,USDT & WETH for ePyvcrv3crypto", async () => {
      const amountUSDT = ethers.utils.parseUnits("5000", 6);
      const amountWBTC = ethers.utils.parseUnits("0.02", 8);
      const amountWETH = ethers.utils.parseUnits("1", 18);

      await stealFromWhale({
        recipient: users[1].address,
        token: "USDT",
        amount: amountUSDT,
      });
      await stealFromWhale({
        recipient: users[1].address,
        token: "WBTC",
        amount: amountWBTC,
      });
      await stealFromWhale({
        recipient: users[1].address,
        token: "WETH",
        amount: amountWETH,
      });

      await tokens.USDT.connect(users[1].user).approve(
        zapTokenToPt.address,
        amountUSDT
      );
      await tokens.WBTC.connect(users[1].user).approve(
        zapTokenToPt.address,
        amountWBTC
      );
      await tokens.WETH.connect(users[1].user).approve(
        zapTokenToPt.address,
        amountWETH
      );

      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          USDT: amountUSDT,
          WBTC: amountWBTC,
          WETH: amountWETH,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps);

      const ptBalance = await tokens.ePyvcrv3crypto.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });
  });
});
