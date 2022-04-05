import { ethers, waffle } from "hardhat";
import { expect } from "chai";
import { VaultWrapperRegistry } from "typechain/VaultWrapperRegistry";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { boolean } from "hardhat/internal/core/params/argumentTypes";

const { provider } = waffle;

describe("Vault Wrapper Registry", () => {
  let vaultWrapperRegistry: VaultWrapperRegistry;
  let signers: SignerWithAddress[];

  before(async () => {
    await createSnapshot(provider);
    signers = await ethers.getSigners();

    const deployer = await ethers.getContractFactory(
      "VaultWrapperRegistry",
      signers[0]
    );
    vaultWrapperRegistry = await deployer.deploy(signers[0].address);
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
      const mockWPAddress = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      await vaultWrapperRegistry
        .connect(signers[0])
        .validateWPAddress(mockWPAddress);
      const result = await vaultWrapperRegistry
        .connect(signers[0])
        .checkWPValidation(mockWPAddress);
      expect(result).to.be.equal(true);
    });
    it("register wp fails for unauthorized owner", async () => {
      const mockWPAddress = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      const tx = vaultWrapperRegistry
        .connect(signers[1])
        .validateWPAddress(mockWPAddress);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
    it("register wp returns false unregistered address", async () => {
      const mockWPAddress = "0x8dc82c95B8901Db35390Aa4096B643d7724F278D";
      const result = await vaultWrapperRegistry
        .connect(signers[0])
        .checkWPValidation(mockWPAddress);
      expect(result).to.be.equal(false);
    });
  });
  describe("register vault addresses", () => {
    it("registers vault address correctly", async () => {
      const mockVaultAddress = "0x5941DB4d6C500C4FFa57c359eE0C55c6b41D0b61";
      await vaultWrapperRegistry
        .connect(signers[0])
        .validateVaultAddress(mockVaultAddress);
      const result = await vaultWrapperRegistry
        .connect(signers[0])
        .checkVaultValidation(mockVaultAddress);
      expect(result).to.be.equal(true);
    });
    it("register vault fails for unauthorized owner", async () => {
      const mockVaultAddress = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      const tx = vaultWrapperRegistry
        .connect(signers[1])
        .validateVaultAddress(mockVaultAddress);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
    it("register vault returns false unregistered address", async () => {
      const mockVaultAddress = "0x8dc82c95B8901Db35390Aa4096B643d7724F278D";
      const result = await vaultWrapperRegistry
        .connect(signers[0])
        .checkVaultValidation(mockVaultAddress);
      expect(result).to.be.equal(false);
    });
  });
  describe("register wp/vault pair addresses", () => {
    it("registers addresses correctly", async () => {
      const mockWPAddress = "0x6F643Ba6894D8C50c476A3539e1D1690B2194018";
      const mockVaultAddress = "0xB59C7597228fEBccEC3dC0571a7Ee39A26E316B9";
      await vaultWrapperRegistry
        .connect(signers[0])
        .validateAddresses(mockWPAddress, mockVaultAddress);
      // check pair validation
      const result1 = await vaultWrapperRegistry
        .connect(signers[0])
        .checkPairValidation(mockWPAddress, mockVaultAddress);
      expect(result1).to.be.equal(true);
      // check individual mapping validation
      const result2 = await vaultWrapperRegistry
        .connect(signers[0])
        .checkWPValidation(mockWPAddress);
      expect(result2).to.be.equal(true);
      const result3 = await vaultWrapperRegistry
        .connect(signers[0])
        .checkVaultValidation(mockVaultAddress);
      expect(result3).to.be.equal(true);
    });
    it("register vault/wp pair fails for unauthorized owner", async () => {
      const mockWPAddress = "0x6F643Ba6894D8C50c476A3539e1D1690B2194018";
      const mockVaultAddress = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      const tx = vaultWrapperRegistry
        .connect(signers[1])
        .validateAddresses(mockWPAddress, mockVaultAddress);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
    it("register returns false unregistered addresses", async () => {
      const mockWPAddress = "0xb47E7a1fD90630CfC0868d90Cb8F518578010cFe";
      const mockVaultAddress = "0x4294005520c453EB8Fa66F53042cfC79707855c4";
      const result = await vaultWrapperRegistry
        .connect(signers[0])
        .checkPairValidation(mockWPAddress, mockVaultAddress);
      expect(result).to.be.equal(false);
    });
  });
});
