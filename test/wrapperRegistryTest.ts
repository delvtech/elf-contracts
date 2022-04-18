import { ethers, waffle } from "hardhat";
import { expect } from "chai";

import { WrapperRegistry } from "typechain/WrapperRegistry";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

describe("Wrapper Registry", () => {
  let wrapperRegistry: WrapperRegistry;
  let signers: SignerWithAddress[];

  before(async () => {
    await createSnapshot(provider);
    signers = await ethers.getSigners();

    const deployer = await ethers.getContractFactory(
      "WrapperRegistry",
      signers[0]
    );
    wrapperRegistry = await deployer.deploy(signers[0].address);
  });
  after(async () => {
    await restoreSnapshot(provider);
  });
  beforeEach(async () => {
    await createSnapshot(provider);
  });
  afterEach(async () => {
    await restoreSnapshot(provider);
  });
  describe("register wrapped position addresses", () => {
    it("registers wp address correctly", async () => {
      const mockWrapper1 = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      // register the address
      await wrapperRegistry.connect(signers[0]).registerWrapper(mockWrapper1);
      // grab the registry
      const result1 = await wrapperRegistry.connect(signers[0]).viewRegistry();
      // registry should only contain the new wp address
      expect(result1).to.eql([mockWrapper1]);
      // check registering a second address
      const mockWrapper2 = "0x8dc82c95B8901Db35390Aa4096B643d7724F278D";
      await wrapperRegistry.connect(signers[0]).registerWrapper(mockWrapper2);
      const result2 = await wrapperRegistry.connect(signers[0]).viewRegistry();
      expect(result2).to.eql([mockWrapper1, mockWrapper2]);
    });
    it("fails to register from unauthorized owner", async () => {
      const mockWPAddress = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      const tx = wrapperRegistry
        .connect(signers[1])
        .registerWrapper(mockWPAddress);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
  });
});
