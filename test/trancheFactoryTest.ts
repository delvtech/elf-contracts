// SPDX-License-Identifier: Apache-2.0

import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import {
  loadTrancheFactoryFixture,
  TrancheFactoryFixture,
} from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

describe("TrancheFactory", () => {
  let fixture: TrancheFactoryFixture;
  let users: { user: Signer; address: string }[];
  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);
    fixture = await loadTrancheFactoryFixture();
    // begin to populate the user array by assigning each index a signer
    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return { user, address: "" };
    });
    // finish populating the user array by assigning each index a signer address
    // and approve 6e6 usdc to the elf contract for each address
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
  describe.only("deployTranche", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should correctly deploy a new tranche instance", async () => {
      const tranche = await fixture.trancheFactory.deployTranche(
        5000000,
        fixture.elf.address
      );
      const eventFilter = fixture.trancheFactory.filters.TrancheCreated(null);
      const events = await fixture.trancheFactory.queryFilter(eventFilter);
      const address = events[0] && events[0].args && events[0].args[0];
      console.log(address);

      const finalBytecode = ethers.utils.solidityPack(
        ["bytes", "bytes"],
        [
          fixture.bytecode,
          ethers.utils.defaultAbiCoder.encode(
            ["address", "uint256"],
            [fixture.elf.address, 5000000]
          ),
        ]
      );
      const salt = ethers.utils.solidityKeccak256(
        ["address", "uint256"],
        [fixture.elf.address, 5000000]
      );
      const bytecodeHash = ethers.utils.solidityKeccak256(
        ["bytes"],
        [finalBytecode]
      );
      const addressbytes = ethers.utils.solidityKeccak256(
        ["bytes1", "address", "bytes32", "bytes32"],
        [0xff, fixture.trancheFactory.address, salt, bytecodeHash]
      );
      console.log(addressbytes);
    });
    it("should fail to deploy to the same address ", async () => {
      await fixture.trancheFactory.deployTranche(5000000, fixture.elf.address);
      await expect(
        fixture.trancheFactory.deployTranche(5000000, fixture.elf.address)
      ).to.be.revertedWith("CREATE2 failed");
    });
  });
});
