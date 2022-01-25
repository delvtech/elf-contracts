import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import { CFixtureInterface, loadCFixture } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

import { impersonate, stopImpersonating } from "./helpers/impersonate";
import { subError } from "./helpers/math";

const { provider } = waffle;

describe("Compound Asset Proxy", () => {
  let users: { user: Signer; address: string }[];
  let fixture: CFixtureInterface;
  // address of a large usdc holder to impersonate. 69 million usdc as of block 11860000
  const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";

  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    const signers = await ethers.getSigners();
    // load all related contracts
    fixture = await loadCFixture(signers[0]);

    // begin to populate the user array by assigning each index a signer
    users = signers.map(function (user) {
      return { user, address: "" };
    });

    // finish populating the user array by assigning each index a signer address
    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    impersonate(usdcWhaleAddress);
    const usdcWhale = await ethers.provider.getSigner(usdcWhaleAddress);

    await fixture.usdc.connect(usdcWhale).transfer(users[0].address, 2e11); // 200k usdc
    await fixture.usdc.connect(usdcWhale).transfer(users[1].address, 2e11); // 200k usdc
    await fixture.usdc.connect(usdcWhale).transfer(users[2].address, 2e11); // 200k usdc

    stopImpersonating(usdcWhaleAddress);

    await fixture.usdc
      .connect(users[0].user)
      .approve(fixture.position.address, 10e11);
    await fixture.usdc
      .connect(users[1].user)
      .approve(fixture.position.address, 10e11);
  });
  after(async () => {
    // revert back to initial state after all tests pass
    await restoreSnapshot(provider);
  });
  describe("deposit", () => {
    it("deposits correctly", async () => {
      await fixture.position
        .connect(users[0].user)
        .deposit(users[0].address, 2e6);
      const balance = await fixture.position.balanceOf(users[0].address);
      // Allows a 0.01% conversion error
      expect(balance).to.be.at.least(subError(ethers.BigNumber.from(2e6)));
    });
    it("fails to deposit amount greater than available", async () => {
      const tx = fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 10e12);
      await expect(tx).to.be.reverted;
    });
  });
  describe("withdraw", () => {
    it("withdraws correctly", async () => {
      const shareBalance = await fixture.position.balanceOf(users[0].address);
      await fixture.position
        .connect(users[0].user)
        .withdraw(users[0].address, shareBalance, 0);
      expect(await fixture.position.balanceOf(users[0].address)).to.equal(0);
    });
    it("fails to withdraw more shares than in balance", async () => {
      // withdraw 10 shares from user with balance 0
      const tx = fixture.position
        .connect(users[4].user)
        .withdraw(users[4].address, 10, 0);
      await expect(tx).to.be.reverted;
    });
    // test withdrawUnderlying to verify _underlying calculation
    it("withdrawUnderlying correctly", async () => {
      const shareBalance = await fixture.position.balanceOf(users[0].address);
      await fixture.position
        .connect(users[2].user)
        .withdrawUnderlying(users[2].address, shareBalance, 0);
      expect(await fixture.position.balanceOf(users[2].address)).to.equal(0);
    });
  });
  describe("rewards", () => {
    it("collects rewards", async () => {
      // starting balance should be 0
      expect(await fixture.comp.balanceOf(users[0].address)).to.equal(0);
      // collect the rewards
      await fixture.position
        .connect(users[0].user)
        .collectRewards(users[0].address);
      // after collection balance should be nonzero
      const balance = await (
        await fixture.comp.balanceOf(users[0].address)
      ).toNumber();
      expect(balance).to.be.greaterThan(0);
    });
    it("fails for unauthorized user", async () => {
      const tx = fixture.position
        .connect(users[1].user)
        .collectRewards(users[0].address);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
  });
});
