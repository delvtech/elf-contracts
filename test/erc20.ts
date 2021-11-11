import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { TestERC20 } from "typechain/TestERC20";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { PERMIT_TYPEHASH } from "./helpers/signatures";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { getDigest } from "./helpers/signatures";
import { impersonate } from "./helpers/impersonate";
import { ecsign } from "ethereumjs-util";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

const { provider } = waffle;

describe("erc20", function () {
  let token: TestERC20;
  const [wallet] = provider.getWallets();
  let signers: SignerWithAddress[];

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();
    const deployer = new TestERC20__factory(signers[0]);
    token = await deployer.deploy("token", "TKN", 18);
    await token.setBalance(signers[0].address, ethers.utils.parseEther("100"));
  });
  after(async () => {
    await restoreSnapshot(provider);
  });

  describe("Permit function", async () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });

    it("has a correctly precomputed typehash", async function () {
      expect(await token.PERMIT_TYPEHASH()).to.equal(PERMIT_TYPEHASH);
    });
    it("Allows valid permit call", async () => {
      const domainSeparator = await token.DOMAIN_SEPARATOR();
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigest(
        "USD Coin",
        domainSeparator,
        token.address,
        wallet.address,
        token.address,
        ethers.constants.MaxUint256,
        nonce,
        ethers.constants.MaxUint256
      );

      const { v, r, s } = ecsign(
        Buffer.from(digest.slice(2), "hex"),
        Buffer.from(wallet.privateKey.slice(2), "hex")
      );
      // impersonate wallet to get Signer for connection
      impersonate(wallet.address);
      const walletSigner = ethers.provider.getSigner(wallet.address);
      await token
        .connect(walletSigner)
        .permit(
          wallet.address,
          token.address,
          ethers.constants.MaxUint256,
          ethers.constants.MaxUint256,
          v,
          r,
          s
        );
    });
    it("Fails invalid permit call", async () => {
      const domainSeparator = await token.DOMAIN_SEPARATOR();
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigest(
        "USD Coin",
        domainSeparator,
        token.address,
        wallet.address,
        token.address,
        ethers.constants.MaxUint256,
        nonce,
        ethers.constants.MaxUint256
      );

      const { v, r, s } = ecsign(
        Buffer.from(digest.slice(2), "hex"),
        Buffer.from(wallet.privateKey.slice(2), "hex")
      );
      // impersonate wallet to get Signer for connection
      impersonate(wallet.address);
      const walletSigner = ethers.provider.getSigner(wallet.address);
      const tx = token
        .connect(walletSigner)
        .permit(
          wallet.address,
          token.address,
          ethers.constants.MaxUint256,
          ethers.constants.MaxUint256,
          v + 1,
          r,
          s
        );
      await expect(tx).to.be.revertedWith("ERC20: invalid-permit");
    });
  });

  describe("transfer functionality", async () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });

    it("transfers successfully", async () => {
      await token.transfer(signers[1].address, ethers.utils.parseEther("5"));
      expect(await token.balanceOf(signers[0].address)).to.be.eq(
        ethers.utils.parseEther("95")
      );
      expect(await token.balanceOf(signers[1].address)).to.be.eq(
        ethers.utils.parseEther("5")
      );
    });
    it("does not transfer more than balance", async () => {
      const tx = token.transfer(
        signers[1].address,
        ethers.utils.parseEther("500")
      );
      await expect(tx).to.be.revertedWith("ERC20: insufficient-balance");
    });
    it("transferFrom successfully", async () => {
      await token.approve(signers[1].address, ethers.utils.parseEther("5"));
      await token
        .connect(signers[1])
        .transferFrom(
          signers[0].address,
          signers[2].address,
          ethers.utils.parseEther("4")
        );
      expect(await token.balanceOf(signers[0].address)).to.be.eq(
        ethers.utils.parseEther("96")
      );
      expect(await token.balanceOf(signers[2].address)).to.be.eq(
        ethers.utils.parseEther("4")
      );
      expect(
        await token.allowance(signers[0].address, signers[1].address)
      ).to.be.eq(ethers.utils.parseEther("1"));
    });
    it("does not decrement unlimited allowance", async () => {
      await token.approve(signers[1].address, ethers.constants.MaxUint256);
      await token
        .connect(signers[1])
        .transferFrom(
          signers[0].address,
          signers[2].address,
          ethers.utils.parseEther("4")
        );
      expect(await token.balanceOf(signers[0].address)).to.be.eq(
        ethers.utils.parseEther("96")
      );
      expect(await token.balanceOf(signers[2].address)).to.be.eq(
        ethers.utils.parseEther("4")
      );
      expect(
        await token.allowance(signers[0].address, signers[1].address)
      ).to.be.eq(ethers.constants.MaxUint256);
    });
    it("blocks invalid transferFrom", async () => {
      const tx = token
        .connect(signers[1])
        .transferFrom(
          signers[0].address,
          signers[2].address,
          ethers.utils.parseEther("5")
        );
      await expect(tx).to.be.revertedWith("ERC20: insufficient-allowance");
    });
  });
});
