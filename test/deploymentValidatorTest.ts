import { ethers, waffle } from "hardhat";
import { expect } from "chai";
import { DeploymentValidator } from "typechain/DeploymentValidator";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { boolean } from "hardhat/internal/core/params/argumentTypes";

const { provider } = waffle;

describe("Deployment Validator", () => {
  let deploymentValidator: DeploymentValidator;
  let signers: SignerWithAddress[];

  before(async () => {
    await createSnapshot(provider);
    signers = await ethers.getSigners();

    const deployer = await ethers.getContractFactory(
      "DeploymentValidator",
      signers[0]
    );
    deploymentValidator = await deployer.deploy(signers[0].address);
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

  describe("validate wrapped position addresses", () => {
    it("validates wp address correctly", async () => {
      const mockWPAddress = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      await deploymentValidator
        .connect(signers[0])
        .validateWPAddress(mockWPAddress);
      const result = await deploymentValidator
        .connect(signers[0])
        .checkWPValidation(mockWPAddress);
      expect(result).to.be.equal(true);
    });
    it("validate wp fails for unauthorized owner", async () => {
      const mockWPAddress = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      const tx = deploymentValidator
        .connect(signers[1])
        .validateWPAddress(mockWPAddress);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
    it("validate wp returns false unregistered address", async () => {
      const mockWPAddress = "0x8dc82c95B8901Db35390Aa4096B643d7724F278D";
      const result = await deploymentValidator
        .connect(signers[0])
        .checkWPValidation(mockWPAddress);
      expect(result).to.be.equal(false);
    });
  });
  describe("validate pool addresses", () => {
    it("validates pool address correctly", async () => {
      const mockPoolAddress = "0x5941DB4d6C500C4FFa57c359eE0C55c6b41D0b61";
      await deploymentValidator
        .connect(signers[0])
        .validatePoolAddress(mockPoolAddress);
      const result = await deploymentValidator
        .connect(signers[0])
        .checkPoolValidation(mockPoolAddress);
      expect(result).to.be.equal(true);
    });
    it("validate pool fails for unauthorized owner", async () => {
      const mockPoolAddress = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      const tx = deploymentValidator
        .connect(signers[1])
        .validatePoolAddress(mockPoolAddress);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
    it("validate pool returns false unregistered address", async () => {
      const mockPoolAddress = "0x8dc82c95B8901Db35390Aa4096B643d7724F278D";
      const result = await deploymentValidator
        .connect(signers[0])
        .checkPoolValidation(mockPoolAddress);
      expect(result).to.be.equal(false);
    });
  });
  describe("validate wp/pool pair addresses", () => {
    it("validates addresses correctly", async () => {
      const mockWPAddress = "0x6F643Ba6894D8C50c476A3539e1D1690B2194018";
      const mockPoolAddress = "0xB59C7597228fEBccEC3dC0571a7Ee39A26E316B9";
      await deploymentValidator
        .connect(signers[0])
        .validateAddresses(mockWPAddress, mockPoolAddress);
      // check pair validation
      const result1 = await deploymentValidator
        .connect(signers[0])
        .checkPairValidation(mockWPAddress, mockPoolAddress);
      expect(result1).to.be.equal(true);
      // check individual mapping validation
      const result2 = await deploymentValidator
        .connect(signers[0])
        .checkWPValidation(mockWPAddress);
      expect(result2).to.be.equal(true);
      const result3 = await deploymentValidator
        .connect(signers[0])
        .checkPoolValidation(mockPoolAddress);
      expect(result3).to.be.equal(true);
    });
    it("validate pool/wp pair fails for unauthorized owner", async () => {
      const mockWPAddress = "0x6F643Ba6894D8C50c476A3539e1D1690B2194018";
      const mockPoolAddress = "0x814C447a9F58A2b823504Fe2775bA48c843925B6";
      const tx = deploymentValidator
        .connect(signers[1])
        .validateAddresses(mockWPAddress, mockPoolAddress);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
    it("validation returns false unregistered addresses", async () => {
      const mockWPAddress = "0xb47E7a1fD90630CfC0868d90Cb8F518578010cFe";
      const mockPoolAddress = "0x4294005520c453EB8Fa66F53042cfC79707855c4";
      const result = await deploymentValidator
        .connect(signers[0])
        .checkPairValidation(mockWPAddress, mockPoolAddress);
      expect(result).to.be.equal(false);
    });
  });
});
