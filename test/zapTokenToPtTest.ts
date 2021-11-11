import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import {
  ZapCurveLpStruct,
  ZapPtInfoStruct,
  ZapTokenToPt,
} from "typechain/ZapTokenToPt";
import { ONE_ETH, ZERO } from "./helpers/constants";
import {
  IZapCurveTokenToPt,
  loadCurveTokenToPtZapFixture,
} from "./helpers/deployer";
import { impersonate, stopImpersonating } from "./helpers/impersonate";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { ONE_DAY_IN_SECONDS } from "./helpers/time";

const { provider } = waffle;

describe.only("zapTokenToPt", () => {
  let users: { user: Signer; address: string }[];

  let zapTokenToPt: ZapTokenToPt;
  let eP_yvcrvSTETH: IZapCurveTokenToPt["eP_yvcrvSTETH"];

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

    ({ zapTokenToPt, eP_yvcrvSTETH } = await loadCurveTokenToPtZapFixture(
      users[1].address
    ));
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
    let zapEthStethPtInfo: ZapPtInfoStruct;
    let zapEthStethCurveLp: ZapCurveLpStruct;

    before(async () => {
      const { whaleSTETH, balancerPoolId, principalToken, curvePool, roots } =
        eP_yvcrvSTETH;

      impersonate(whaleSTETH._address);

      await eP_yvcrvSTETH.STETH.connect(whaleSTETH).transfer(
        users[1].address,
        ONE_ETH
      );

      zapEthStethPtInfo = {
        balancerPoolId,
        recipient: users[1].address,
        principalToken: principalToken.address,
        minPtAmount: ZERO,
        deadline,
      };

      zapEthStethCurveLp = {
        curvePool: curvePool,
        amounts: [ZERO, ZERO],
        roots,
      };

      stopImpersonating(whaleSTETH._address);
    });

    it.only("should swap ETH for eP:yvcrvSTETH", async () => {
      console.log(zapEthStethPtInfo, zapEthStethCurveLp);
      await zapTokenToPt.connect(users[1].user).zapCurveIn(
        zapEthStethPtInfo,
        {
          ...zapEthStethCurveLp,
          amounts: [ethers.utils.parseEther("1"), ZERO],
        },
        false,
        zapEthStethCurveLp,
        0,
        {
          value: ethers.utils.parseEther("1"),
        }
      );
      const ptBalance = await eP_yvcrvSTETH.principalToken.balanceOf(
        users[1].address
      );
    });

    it("should swap stETH for eP:yvcrvSTETH", async () => {
      await eP_yvcrvSTETH.STETH.connect(users[1].user).approve(
        zapTokenToPt.address,
        ONE_ETH
      );

      await zapTokenToPt
        .connect(users[1].user)
        .zapCurveIn(
          zapEthStethPtInfo,
          { ...zapEthStethCurveLp, amounts: [ZERO, ONE_ETH] },
          false,
          zapEthStethCurveLp,
          0
        );
    });
  });
});
