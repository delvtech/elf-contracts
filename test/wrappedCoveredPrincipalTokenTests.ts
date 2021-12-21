import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { WrappedCoveredPrincipalTokenFactory } from "typechain/WrappedCoveredPrincipalTokenFactory";
import { WrappedCoveredPrincipalToken } from "typechain/WrappedCoveredPrincipalToken";
import { WrappedCoveredPrincipalTokenFactory__factory } from "typechain/factories/WrappedCoveredPrincipalTokenFactory__factory";
import { WrappedCoveredPrincipalToken__factory } from "typechain/factories/WrappedCoveredPrincipalToken__factory";
import { TestERC20 } from "typechain/TestERC20";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { loadTestTrancheFixture, TrancheTestFixture } from "./helpers/deployer";

const { provider } = waffle;

describe("WrappedCoveredPrincipalToken", function () {
  let fixture: TrancheTestFixture;
  let factory: WrappedCoveredPrincipalTokenFactory;
  let coveredToken: WrappedCoveredPrincipalToken;
  let signers: SignerWithAddress[];
  let baseToken: TestERC20;
  let coveredOwner: string;

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();
    const factoryDeployer = new WrappedCoveredPrincipalTokenFactory__factory(
      signers[0]
    );
    const coveredTokenDeployer = new WrappedCoveredPrincipalToken__factory(
      signers[0]
    );

    // load all related contracts
    fixture = await loadTestTrancheFixture();

    coveredOwner = signers[1].address;
    baseToken = fixture.usdc;
    factory = await factoryDeployer.deploy(signers[0].address);
    await factory.create(baseToken.address, coveredOwner);
    coveredToken = coveredTokenDeployer.attach(
      (await factory.allWrappedCoveredPrincipalTokens())[0]
    );
  });
  after(async () => {
    await restoreSnapshot(provider);
  });

  describe("Validate Constructor", async () => {
    it("Should initialize correctly", async () => {
      expect(await coveredToken.owner()).to.equal(coveredOwner);
      expect(await coveredToken.isAuthorized(coveredOwner)).to.true;
      expect(await coveredToken.name()).to.equal(
        "WrappedTESTCovered Principal"
      );
      expect(await coveredToken.symbol()).to.equal("ep:WTEST");
      expect(await coveredToken.baseToken()).to.equal(baseToken.address);
    });
  });

  describe("Tranche mgt", async () => {
    it("should fail to add tranche because msg.sender is not the owner", async () => {
      const tx = coveredToken
        .connect(signers[2])
        .addTranche(fixture.tranche.address);
      await expect(tx).to.be.revertedWith("Sender not owner");
    });
  });
});
