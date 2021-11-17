import { Signer } from "ethers";
import { formatEther } from "ethers/lib/utils";
import { ethers, waffle } from "hardhat";
import {
  ZapCurveLpStruct,
  ZapPtInfoStruct,
  ZapTokenToPt,
} from "typechain/ZapTokenToPt";
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

  let ptInfo: ZapPtInfoStruct;
  let zap: ZapCurveLpStruct;
  let childZaps: ZapCurveLpStruct[];

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

  describe("ETH:STETH -> eP:yvcrvSTETH", () => {
    let constructZapStructs: ZapCurveTokenFixture<"ep_yvcrvSTETH">["constructZapStructs"];
    let tokens: ZapCurveTokenFixture<"ep_yvcrvSTETH">["tokens"];
    let stealFromWhale: ZapCurveTokenFixture<"ep_yvcrvSTETH">["stealFromWhale"];

    before(async () => {
      ({ constructZapStructs, tokens, stealFromWhale } =
        await constructZapFixture({
          zapTrie: {
            ep_yvcrvSTETH: {
              CRV_STETH: ["ETH", "STETH"],
            },
          },
          balancerPoolId:
            "0xb03c6b351a283bc1cd26b9cf6d7b0c4556013bdb0002000000000000000000ab",
          addresses: {
            ETH: _ETH_CONSTANT,
            STETH: "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",
            CRV_STETH: "0x06325440D014e39736583c165C2963BA99fAf14E",
            ep_yvcrvSTETH: "0x2361102893CCabFb543bc55AC4cC8d6d0824A67E",
          },
          pools: {
            CRV_STETH: "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022",
          },
          whales: {
            STETH: "0x06920C9fC643De77B99cB7670A944AD31eaAA260",
          },
        }));
    });

    it("should swap ETH for eP:yvcrvSTETH", async () => {
      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          ETH: ONE_ETH,
          STETH: ZERO,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps, {
          value: ethers.utils.parseEther("1"),
        });

      const ptBalance = await tokens.ep_yvcrvSTETH.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });

    it("should swap stETH for eP:yvcrvSTETH", async () => {
      await stealFromWhale({
        recipient: users[1].address,
        token: "STETH",
        amount: ONE_ETH,
      });

      await tokens.STETH.connect(users[1].user).approve(
        zapTokenToPt.address,
        ONE_ETH
      );

      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          ETH: ZERO,
          STETH: ONE_ETH,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps);

      const ptBalance = await tokens.ep_yvcrvSTETH.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });

    it("should swap stETH and ETH for eP:yvcrvSTETH", async () => {
      await stealFromWhale({
        recipient: users[1].address,
        token: "STETH",
        amount: ONE_ETH,
      });

      await tokens.STETH.connect(users[1].user).approve(
        zapTokenToPt.address,
        ONE_ETH
      );

      const { ptInfo, zap, childZaps } = constructZapStructs(
        {
          ETH: ONE_ETH,
          STETH: ONE_ETH,
        },
        users[1].address,
        0
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(ptInfo, zap, childZaps, { value: ONE_ETH });

      const ptBalance = await tokens.ep_yvcrvSTETH.balanceOf(users[1].address);
      console.log(formatEther(ptBalance));
    });
  });

  // describe("DAI:USDC:USDT -> ep", () => {
  //   let constructZapStructs: ZapCurveTokenFixture<"ep_yvcrv3crypto">["constructZapStructs"];
  //   let tokens: ZapCurveTokenFixture<"ep_yvcrv3crypto">["tokens"];
  //   let stealFromWhale: ZapCurveTokenFixture<"ep_yvcrv3crypto">["stealFromWhale"];

  //   before(async () => {
  //     ({ constructZapStructs, tokens, stealFromWhale } =
  //       await constructZapFixture({
  //         zapTrie: {
  //           ep_yvcrv3crypto: {
  //             THREE_CRV: ["DAI", "USDC", "USDT"],
  //           },
  //         },
  //         balancerPoolId:
  //           "0xb03c6b351a283bc1cd26b9cf6d7b0c4556013bdb0002000000000000000000ab",
  //         addresses: {},
  //         pools: {},
  //         whales: {},
  //       }));
  //   });

  //   it("should swap ETH for eP:yvcrvSTETH", async () => {
  //     const { ptInfo, zap, childZaps } = constructZapStructs(
  //       {
  //         ETH: ONE_ETH,
  //         STETH: ZERO,
  //       },
  //       users[1].address,
  //       0
  //     );

  //     await zapTokenToPt
  //       .connect(users[1].user)
  //       .zapCurveIn(ptInfo, zap, childZaps, {
  //         value: ethers.utils.parseEther("1"),
  //       });

  //     const ptBalance = await tokens.ep_yvcrvSTETH.balanceOf(users[1].address);
  //     console.log(formatEther(ptBalance));
  //   });
  // });
});
