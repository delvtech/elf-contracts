import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import {
  loadTokenToPtZapFixture,
  TokenToPtZapInterface,
} from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { ONE_DAY_IN_SECONDS } from "./helpers/time";

const { provider } = waffle;

describe("zapEthToPt", () => {
  let users: { user: Signer; address: string }[];

  let fixture: TokenToPtZapInterface;
  const curveEthStethPool = "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022";

  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // begin to populate the user array by assigning each index a signer
    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return { user, address: "" };
    });

    // finish populating the user array by assigning each index a signer address
    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    fixture = await loadTokenToPtZapFixture(users[1].address);

    // const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";
    // impersonate(usdcWhaleAddress);
    // const usdcWhale = await ethers.provider.getSigner(usdcWhaleAddress);
    // await fixture.usdc.connect(usdcWhale).transfer(users[1].address, 2e11); // 200k usdc
    // stopImpersonating(usdcWhaleAddress);
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

  it("should swap ETH for eP:yvcrvSTETH", async () => {
    const ethConstant = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

    const inputToken = ethConstant;
    const inputTokenIdx = 0;
    const crvPool = curveEthStethPool;
    const baseToken = fixture.stCRV.address;
    const balancerVault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
    const balancerPoolId =
      "0xb03c6b351a283bc1cd26b9cf6d7b0c4556013bdb0002000000000000000000ab";
    const principalToken = fixture.ePyvcrvSTETH.address;

    const inputTokenAmount = ethers.utils.parseEther("10");
    const minPtAmount = "0";
    const deadline = Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS;

    const zapInData = {
      inputToken,
      inputTokenIdx,
      crvPool,
      baseToken,
      balancerVault,
      balancerPoolId,
      principalToken,
    };

    await fixture.zapEthToPt
      .connect(users[1].user)
      .zapIn(
        zapInData,
        inputTokenAmount,
        users[1].address,
        minPtAmount,
        deadline,
        {
          value: inputTokenAmount,
        }
      );

    //const ptBalance = await fixture.ePyvcrvSTETH.balanceOf(users[1].address);
    //console.log("eP:yvcrvSTETH balance:", ptBalance.toString());
  });
});
