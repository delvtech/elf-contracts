import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import {
  loadYearnShareZapFixture,
  YearnShareZapInterface,
} from "./helpers/deployer";
import { impersonate, stopImpersonating } from "./helpers/impersonate";
import { subError } from "./helpers/math";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

describe("zapYearnShares", () => {
  let users: { user: Signer; address: string }[];
  let fixture: YearnShareZapInterface;

  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);
    fixture = await loadYearnShareZapFixture();

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
    // get USDC
    const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";
    impersonate(usdcWhaleAddress);
    const usdcWhale = ethers.provider.getSigner(usdcWhaleAddress);
    await fixture.usdc.connect(usdcWhale).transfer(users[1].address, 2e11); // 200k usdc
    stopImpersonating(usdcWhaleAddress);
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

  describe("zapSharesIn", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });

    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should fail with incorrect PT expected", async () => {
      // deposit value directly into the yearn vault
      await fixture.usdc
        .connect(users[1].user)
        .approve(fixture.yusdc.address, 2e11);
      await fixture.yusdc
        .connect(users[1].user)
        .deposit(2e11, users[1].address);
      const shares = await fixture.yusdc.balanceOf(users[1].address);

      // zap shares into PT and YT
      const expiration = (await fixture.tranche.unlockTimestamp()).toNumber();
      await fixture.yusdc
        .connect(users[1].user)
        .approve(fixture.sharesZapper.address, shares);
      const tx = fixture.sharesZapper
        .connect(users[1].user)
        .zapSharesIn(
          fixture.usdc.address,
          fixture.yusdc.address,
          shares,
          expiration,
          fixture.position.address,
          shares.mul(2)
        );
      await expect(tx).to.be.revertedWith("Not enough PT minted");
    });
    it("should correctly zap shares in", async () => {
      // deposit value directly into the yearn vault
      await fixture.usdc
        .connect(users[1].user)
        .approve(fixture.yusdc.address, 2e11);
      await fixture.yusdc
        .connect(users[1].user)
        .deposit(2e11, users[1].address);
      const shares = await fixture.yusdc.balanceOf(users[1].address);
      // zap shares into PT and YT
      const expiration = (await fixture.tranche.unlockTimestamp()).toNumber();
      await fixture.yusdc
        .connect(users[1].user)
        .approve(fixture.sharesZapper.address, shares);
      await fixture.sharesZapper
        .connect(users[1].user)
        .zapSharesIn(
          fixture.usdc.address,
          fixture.yusdc.address,
          shares,
          expiration,
          fixture.position.address,
          shares
        );
      const pricePerFullShare = await fixture.yusdc.pricePerShare();
      const balance = (await fixture.yusdc.balanceOf(fixture.position.address))
        .mul(pricePerFullShare)
        .div(ethers.utils.parseUnits("1", 6));
      // Allows a 0.01% conversion error
      expect(balance).to.be.at.least(subError(ethers.BigNumber.from(1e11)));
    });
  });
});
