import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { ZapCurveInStruct } from "typechain/ZapTokenToPt";
import { _ETH_CONSTANT } from "./helpers/constants";
import {
  loadTokenToPtZapFixture,
  TokenToPtZapInterface,
} from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { ONE_DAY_IN_SECONDS } from "./helpers/time";

import { impersonate, stopImpersonating } from "./helpers/impersonate";

const { provider } = waffle;

describe.only("zapTokenToPt", () => {
  let users: { user: Signer; address: string }[];

  let fixture: TokenToPtZapInterface;

  let zap: ZapCurveInStruct;

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

    fixture = await loadTokenToPtZapFixture(users[1].address);
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
    before(async () => {
      const stEthWhaleAddress = "0x62e41b1185023bcc14a465d350e1dde341557925";
      const stEthWhale = ethers.provider.getSigner(stEthWhaleAddress);

      impersonate(stEthWhaleAddress);
      await fixture.stETH
        .connect(stEthWhale)
        .transfer(users[1].address, ethers.utils.parseEther("1"));

      zap = {
        curvePool: "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022",
        balancerPoolId:
          "0xb03c6b351a283bc1cd26b9cf6d7b0c4556013bdb0002000000000000000000ab",
        amounts: [ethers.utils.parseEther("1"), "0"],
        tokens: [_ETH_CONSTANT, fixture.stETH.address],
        recipient: users[1].address,
        principalToken: fixture.ePyvcrvSTETH.address, // eP:yvcrvSTETH
        minPtAmount: "0",
        deadline: Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS,
      };
    });

    it("should swap ETH for eP:yvcrvSTETH", async () => {
      await fixture.zapTokenToPt.connect(users[1].user).zapCurveIn(zap, {
        value: zap.amounts[0],
      });
      const ptBalance = await fixture.ePyvcrvSTETH.balanceOf(users[1].address);
    });

    it.only("should swap stETH for eP:yvcrvSTETH", async () => {
      await fixture.stETH
        .connect(users[1].user)
        .approve(fixture.zapTokenToPt.address, ethers.constants.MaxUint256);
      await fixture.zapTokenToPt.connect(users[1].user).zapCurveIn({
        ...zap,
        amounts: ["0", ethers.utils.parseEther("0.5")],
      });
    });
  });
});
