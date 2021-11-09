import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { loadFixture, FixtureInterface } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

describe("TrancheFactory", () => {
  let fixture: FixtureInterface;
  let users: { user: Signer; address: string }[];
  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);
    fixture = await loadFixture();
    // begin to populate the user array by assigning each index a signer
    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return { user, address: "" };
    });
    // finish populating the user array by assigning each index a signer address
    // and approve 6e6 usdc to the position contract for each address
    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );
  });
  after(async () => {
    // revert back to initial state after all tests pass
    await restoreSnapshot(provider);
  });
  describe("deployTranche", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should correctly deploy a new tranche instance", async () => {
      expect(
        await fixture.proxy.deriveTranche(fixture.position.address, 1e10)
      ).to.equal(fixture.tranche.address);
    });
    it("should fail to deploy to the same address ", async () => {
      await expect(
        fixture.trancheFactory.deployTranche(1e10, fixture.position.address)
      ).to.be.reverted;
    });
  });
});
