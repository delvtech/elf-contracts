import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import { CFixtureInterface, loadCFixture } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { setBlock } from "test/helpers/forking";

import { CompoundAssetProxy } from "typechain/CompoundAssetProxy";

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

    // load all related contracts
    fixture = await loadCFixture();

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
    ).to.equal(1e6);
  });
});
