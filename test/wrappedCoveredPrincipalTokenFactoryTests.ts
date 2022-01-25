import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { WrappedCoveredPrincipalTokenFactory } from "typechain/WrappedCoveredPrincipalTokenFactory";
import { WrappedCoveredPrincipalTokenFactory__factory } from "typechain/factories/WrappedCoveredPrincipalTokenFactory__factory";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { loadFixture, FixtureInterface } from "./helpers/deployer";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import data from "../artifacts/contracts/Tranche.sol/Tranche.json";

const { provider } = waffle;

describe("WrappedCoveredPrincipalTokenFactory", function () {
  let factory: WrappedCoveredPrincipalTokenFactory;
  let signers: SignerWithAddress[];
  let fixture: FixtureInterface;

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();
    fixture = await loadFixture();
    const bytecodehash = ethers.utils.solidityKeccak256(
      ["bytes"],
      [data.bytecode]
    );
    const deployer = new WrappedCoveredPrincipalTokenFactory__factory(
      signers[0]
    );
    factory = await deployer.deploy(
      fixture.trancheFactory.address,
      bytecodehash
    );
  });
  after(async () => {
    await restoreSnapshot(provider);
  });

  describe("Create Wrapped PrincipalToken", async () => {
    let deployer: any;
    let contractOwner: any;

    before(async function () {
      await createSnapshot(provider);
      signers = await ethers.getSigners();
      deployer = new TestERC20__factory(signers[0]);
      contractOwner = await ethers.provider.getSigner(signers[1].address);
    });

    it("should fail to create because of zero address of owner", async () => {
      const owner = "0x0000000000000000000000000000000000000000";
      const baseToken = await deployer.deploy("Token", "TKN", 18);
      const tx = factory
        .connect(contractOwner)
        .create(baseToken.address, owner, { from: signers[1].address });
      await expect(tx).to.be.revertedWith("WFPF:ZERO_ADDRESS");
    });

    it("should fail to create because of zero address of base token", async () => {
      const owner = signers[2].address;
      const baseToken = "0x0000000000000000000000000000000000000000";
      const tx = factory
        .connect(contractOwner)
        .create(baseToken, owner, { from: signers[1].address });
      await expect(tx).to.be.revertedWith("WFPF:ZERO_ADDRESS");
    });

    it("should successfully create the wrapped covered token", async () => {
      const owner = signers[2].address;
      const baseToken = await deployer.deploy("Token", "TKN", 18);
      await factory
        .connect(contractOwner)
        .create(baseToken.address, owner, { from: signers[1].address });
      expect(
        (await factory.allWrappedCoveredPrincipalTokens()).length
      ).to.equal(1);
    });
  });
});
