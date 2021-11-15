import { Signer } from "ethers";
import { formatEther } from "ethers/lib/utils";
import { ethers, waffle } from "hardhat";
import {
  ZapCurveLpStruct,
  ZapPtInfoStruct,
  ZapTokenToPt,
} from "typechain/ZapTokenToPt";
import { ZERO, _ETH_CONSTANT } from "./helpers/constants";
import {
  initZapCurveTokenToPt,
  Roots,
  PrincipalTokens,
  ZapCurveTokenFixture,
  ZapCurveTokenFixtureConstructorFn,
} from "./helpers/deployZapCurveTokenToPt";
import { impersonate, stopImpersonating } from "./helpers/impersonate";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { ONE_DAY_IN_SECONDS } from "./helpers/time";

const { provider } = waffle;

describe.only("zapTokenToPt", () => {
  let users: { user: Signer; address: string }[];

  let zapTokenToPt: ZapTokenToPt;
  let constructZapFixture: ZapCurveTokenFixtureConstructorFn<
    PrincipalTokens,
    Roots
  >;

  const deadline = Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS;

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

    ({ zapTokenToPt, constructZapCurveTokenFixture: constructZapFixture } =
      await initZapCurveTokenToPt(users[1].address));
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
    let fixture: ZapCurveTokenFixture<PrincipalTokens, Roots>;
    let zapEthStethPtInfo: ZapPtInfoStruct;
    let zapEthStethCurveLp: ZapCurveLpStruct;

    before(async () => {
      fixture = await constructZapFixture({
        pt: "eP_yvcrvSTETH",
        roots: ["ETH", "STETH"],
        rootAddresses: [
          _ETH_CONSTANT,
          "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",
        ],
        rootWhales: [null, "0x62e41b1185023bcc14a465d350e1dde341557925"],
        curvePoolAddress: "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022",
        principalTokenAddress: "0x2361102893CCabFb543bc55AC4cC8d6d0824A67E",
        balancerPoolId:
          "0xb03c6b351a283bc1cd26b9cf6d7b0c4556013bdb0002000000000000000000ab",
      });

      const {
        balancerPoolId,
        eP_yvcrvSTETH,
        curvePool,
        roots,
        STETH,
        whaleSTETH,
      } = fixture;

      impersonate(whaleSTETH);
      const whaleSTETHSigner = ethers.provider.getSigner(whaleSTETH);

      await STETH.connect(whaleSTETHSigner).transfer(
        users[1].address,
        ethers.utils.parseEther("1")
      );

      zapEthStethPtInfo = {
        balancerPoolId,
        recipient: users[1].address,
        principalToken: eP_yvcrvSTETH.address,
        minPtAmount: ZERO,
        deadline,
      };

      zapEthStethCurveLp = {
        curvePool: curvePool.address,
        amounts: [ZERO, ZERO],
        roots: roots.map((tkn) => fixture[tkn].address),
      };

      stopImpersonating(whaleSTETH);
    });

    it.only("should swap ETH for eP:yvcrvSTETH", async () => {
      const amounts = [ethers.utils.parseEther("1"), ZERO];
      const minPtAmount = await fixture.calcMinPtAmount(amounts);
      console.log(
        "minPtAmount:",
        formatEther(ethers.utils.parseUnits(minPtAmount.toString(), "wei"))
      );
      await zapTokenToPt.connect(users[1].user).zapCurveIn(
        { ...zapEthStethPtInfo, minPtAmount: ZERO },
        {
          ...zapEthStethCurveLp,
          amounts,
        },
        false,
        zapEthStethCurveLp,
        0,
        {
          value: ethers.utils.parseEther("1"),
        }
      );
      const ptBalance = await fixture.eP_yvcrvSTETH.balanceOf(users[1].address);

      console.log("ptAmount", formatEther(ptBalance));
    });

    it("should swap stETH for eP:yvcrvSTETH", async () => {
      await fixture.STETH.connect(users[1].user).approve(
        zapTokenToPt.address,
        ethers.utils.parseEther("100")
      );

      await zapTokenToPt.connect(users[1].user).zapCurveIn(
        zapEthStethPtInfo,
        {
          ...zapEthStethCurveLp,
          amounts: [ZERO, ethers.utils.parseEther("100")],
        },
        false,
        zapEthStethCurveLp,
        0
      );
      const ptBalance = await fixture.eP_yvcrvSTETH.balanceOf(users[1].address);
      console.log(ptBalance.toString());
    });
  });
});
