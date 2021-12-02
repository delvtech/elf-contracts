import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import { CFixtureInterface, loadCFixture } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

import { impersonate, stopImpersonating } from "./helpers/impersonate";

const { provider } = waffle;

describe.only("Compound Asset Proxy", () => {
  let users: { user: Signer; address: string }[];
  let fixture: CFixtureInterface;
  // address of a large usdc holder to impersonate. 69 million usdc as of block 11860000
  const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";
  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    const signers = await ethers.getSigners();
    // load all related contracts
    // TODO: pass signers into this here
    fixture = await loadCFixture(signers[2]);

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
  it("deposit", async () => {
    await fixture.position
      .connect(users[0].user)
      .deposit(users[0].address, 1e6);
    expect(
      await fixture.position.balanceOfUnderlying(users[0].address)
    ).to.equal(2); // TODO: I'm not sure if this should actually equal 2
    // I think it's because of the exchange rate?
    // Am I checking the right value?
  });
  it("withdraw", async () => {
    const shareBalance = await fixture.position.balanceOf(users[0].address);
    await fixture.position
      .connect(users[0].user)
      .withdraw(users[0].address, shareBalance, 0);
    expect(await fixture.position.balanceOf(users[0].address)).to.equal(0);
  });
  it("rewards", async () => {
    // transfer some comp so we have something to collect
    const compWhaleAddress = "0x0f50d31b3eaefd65236dd3736b863cffa4c63c4e";
    impersonate(compWhaleAddress);
    const compWhale = await ethers.provider.getSigner(compWhaleAddress);

    // check the whale's balance

    // collect the rewards
    const owner = await fixture.position.owner();
    const rewardBalance = await fixture.position.collectRewards(owner);

    // check the comp balance
    console.log(`Rewards: ${rewardBalance}`);
    stopImpersonating(usdcWhaleAddress);
  });
});
