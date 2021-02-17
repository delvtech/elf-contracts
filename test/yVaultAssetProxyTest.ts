import {ethers} from "hardhat";
import {loadFixture, fixtureInterface} from "./helpers/deployer";
import {createSnapshot, restoreSnapshot} from "./helpers/snapshots";

import {expect} from "chai";
import {AddressZero} from "@ethersproject/constants";
import {Signer} from "ethers";

const {waffle} = require("hardhat");
const provider = waffle.provider;

describe("YVaultAssetProxy", () => {
  let fixture: fixtureInterface;
  let deployer: Signer;
  let user: Signer;
  let deployerAddress: string;
  let userAddress: string;
  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts
    fixture = await loadFixture();
    [deployer, user] = await ethers.getSigners();
    deployerAddress = await deployer.getAddress();
    userAddress = await user.getAddress();
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
  describe("setGovernance", () => {
    it("should not be callable by non-approved caller", async () => {
      await expect(
        fixture.yusdcAsset.connect(user).setGovernance(AddressZero)
      ).to.be.revertedWith("!governance");
    });
    it("should be callable by approved caller", async () => {
      await fixture.yusdcAsset.connect(deployer).setGovernance(AddressZero);
      expect(await fixture.yusdcAsset.governance()).to.equal(AddressZero);
    });
  });
  describe("setPool", () => {
    it("should not be callable by non-approved caller", async () => {
      await expect(
        fixture.yusdcAsset.connect(user).setPool(AddressZero)
      ).to.be.revertedWith("!governance");
    });
    it("should be callable by approved caller", async () => {
      await fixture.yusdcAsset.connect(deployer).setPool(AddressZero);
      expect(await fixture.yusdcAsset.pool()).to.equal(AddressZero);
    });
  });
  describe("deposit", () => {
    it("should correctly deposit value", async () => {
      // we use deployer here since they already have a usdc balance
      await fixture.usdc
        .connect(deployer)
        .transfer(fixture.yusdcAsset.address, 1e6);
      await fixture.yusdcAsset.deposit();

      expect(await fixture.yusdcAssetVault.balanceOf(deployerAddress)).to.equal(
        1e6
      );
    });
    it("should correctly withdraw value", async () => {
      // we use deployer here since they already have a usdc balance
      const initialUsdcBalance = await fixture.usdc.balanceOf(deployerAddress);
      await fixture.usdc
        .connect(deployer)
        .transfer(fixture.yusdcAsset.address, 1e6);
      await fixture.yusdcAsset.deposit();

      const daployerVaultBalance = await fixture.yusdcAssetVault.balanceOf(
        deployerAddress
      );

      await fixture.yusdcAssetVault.transfer(
        fixture.yusdcAsset.address,
        daployerVaultBalance
      );
      await fixture.yusdcAsset.withdraw();
      expect(await fixture.usdc.balanceOf(deployerAddress)).to.equal(
        initialUsdcBalance
      );
    });
  });
});
