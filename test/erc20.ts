import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { TestERC20 } from "typechain/TestERC20";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { PERMIT_TYPEHASH } from "./helpers/signatures";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { getDigest } from "./helpers/signatures";
import { impersonate } from "./helpers/impersonate";
import { ecsign } from "ethereumjs-util";

const { provider } = waffle;

describe("erc20", function () {
  let token: TestERC20;
  const [wallet] = provider.getWallets();
  before(async function () {
    await createSnapshot(provider);
    const [signer] = await ethers.getSigners();
    const deployer = new TestERC20__factory(signer);
    token = await deployer.deploy("token", "TKN", 18);
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
    const walletSigner = await ethers.provider.getSigner(wallet.address);
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
    const walletSigner = await ethers.provider.getSigner(wallet.address);
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
    await expect(tx).to.be.revertedWith("revert ERC20: invalid-permit");
  });
});
