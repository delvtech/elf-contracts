import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import {
  loadUsdcPoolMainnetFixture,
  UsdcPoolMainnetInterface,
  EthPoolMainnetInterface,
  loadEthPoolMainnetFixture,
} from "./helpers/deployer";
import { impersonate } from "./helpers/impersonate";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { getDigest } from "./helpers/signatures";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { CodeSizeChecker__factory } from "typechain/factories/CodeSizeChecker__factory";
import { Signer, utils } from "ethers";
import { MockProvider } from "ethereum-waffle";
import { ecsign } from "ethereumjs-util";

const { provider } = waffle;

describe("UserProxyTests", function () {
  let usdcFixture: UsdcPoolMainnetInterface;

  let proxy: Contract;
  let underlying: Contract;
  let signers: SignerWithAddress[];
  const lots = ethers.utils.parseUnits("1000000", 6);
  const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";

  before(async function () {
    await createSnapshot(provider);
    // Get the setup contracts
    usdcFixture = await loadUsdcPoolMainnetFixture();
    ({ proxy } = usdcFixture);

    underlying = await ethers.getContractAt(
      "contracts/libraries/ERC20Permit.sol:ERC20Permit",
      await usdcFixture.position.token()
    );
    impersonate(usdcWhaleAddress);
    const usdcWhale = await ethers.provider.getSigner(usdcWhaleAddress);
    // Get the signers
    signers = await ethers.getSigners();
    // mint to the user 0
    await underlying.connect(usdcWhale).transfer(signers[0].address, lots);
    // mint to the user 1
    await underlying.connect(usdcWhale).transfer(signers[1].address, lots);

    // Make an initial deposit in the aypool contract
    // This prevents a div by zero reversion in several cases
    await usdcFixture.usdc.connect(usdcWhale).transfer(signers[0].address, 100);
    await usdcFixture.usdc.approve(usdcFixture.yusdc.address, 100);
    await usdcFixture.yusdc.deposit(100, signers[0].address);

    // Make a gas reserve deposit to test that logic
    const twohundred = ethers.utils.parseUnits("200", 6);
    await usdcFixture.usdc
      .connect(usdcWhale)
      .approve(usdcFixture.position.address, twohundred.mul(2));
    await usdcFixture.position.connect(usdcWhale).reserveDeposit(twohundred);
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
  it("Successfully derives tranche contract address", async function () {
    const addr = await usdcFixture.proxy.deriveTranche(
      usdcFixture.position.address,
      1e10
    );
    expect(addr).to.equal(usdcFixture.tranche.address);
  });
  it("Successfully mints", async function () {
    // To avoid messing with permit we use the allowance method
    await underlying.approve(proxy.address, lots);

    let receipt = await proxy.mint(
      ethers.utils.parseUnits("1", 6),
      underlying.address,
      1e10,
      usdcFixture.position.address,
      []
    );
    // Mint for the first time
    receipt = await receipt.wait();
    console.log("First Mint", receipt.gasUsed.toNumber());
    receipt = await proxy.mint(
      ethers.utils.parseUnits("1", 6),
      underlying.address,
      1e10,
      usdcFixture.position.address,
      []
    );
    receipt = await receipt.wait();
    console.log("Repeat Mint", receipt.gasUsed.toNumber());
    // Set an approval for the new user
    await underlying.connect(signers[1]).approve(proxy.address, lots);
    receipt = await proxy
      .connect(signers[1])
      .mint(
        ethers.utils.parseUnits("1", 6),
        underlying.address,
        1e10,
        usdcFixture.position.address,
        []
      );
    receipt = await receipt.wait();
    console.log("New User First mint", receipt.gasUsed.toNumber());
  });
  describe("Deprecation function", async () => {
    it("Blocks deprecation by non owners", async () => {
      const tx = proxy.connect(signers[1]).deprecate();
      expect(tx).to.be.revertedWith("Sender not owner");
    });
    it("Allows deprecation by the owner", async () => {
      const deployer = new CodeSizeChecker__factory(signers[0]);
      const sizeChecker = await deployer.deploy();
      const sizeBefore = sizeChecker.codeSize(proxy.address);
      expect(sizeBefore).to.not.be.eq(0);
      await proxy.deprecate();
      const sizeAfter = await sizeChecker.codeSize(proxy.address);
      expect(sizeAfter).to.be.eq(0);
    });
  });
  describe("WETH mint", async () => {
    let wethFixture: EthPoolMainnetInterface;
    let users: { user: Signer; address: string }[];

    before(async function () {
      wethFixture = await loadEthPoolMainnetFixture();
      users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
        return { user, address: "" };
      });
      await Promise.all(
        users.map(async (userInfo) => {
          const { user } = userInfo;
          userInfo.address = await user.getAddress();
        })
      );
    });
    it("Reverts with value mismatch", async () => {
      await expect(
        wethFixture.proxy
          .connect(users[1].user)
          .mint(
            ethers.utils.parseUnits("1", 18),
            "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            1e10,
            wethFixture.position.address,
            [],
            { value: utils.parseEther("2") }
          )
      ).to.be.revertedWith("Incorrect amount provided");
    });
    it("Correctly mints with WETH", async () => {
      await wethFixture.proxy
        .connect(users[1].user)
        .mint(
          ethers.utils.parseUnits("1", 18),
          "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
          1e10,
          wethFixture.position.address,
          [],
          { value: utils.parseEther("1") }
        );
      const trancheValue = await wethFixture.tranche.balanceOf(
        users[1].address
      );
      expect(trancheValue).to.be.eq(
        ethers.BigNumber.from(utils.parseEther("1"))
      );
    });
  });

  describe("erc20 Permit mint", async () => {
    const provider: MockProvider = new MockProvider();
    // use Wallet instead of Signer because it is easy to get private key
    const [wallet] = provider.getWallets();

    before(async function () {
      const signers = await ethers.getSigners();
      // Send 1 ether to an caller for gas fees.
      await signers[0].sendTransaction({
        to: wallet.address,
        value: ethers.utils.parseEther("1.0"),
      });
      // transfer usdc to wallet address
      impersonate(usdcWhaleAddress);
      const tokenHolder = await ethers.provider.getSigner(usdcWhaleAddress);
      await usdcFixture.usdc.connect(tokenHolder).transfer(wallet.address, 100);
      underlying = await ethers.getContractAt(
        "contracts/libraries/ERC20.sol:ERC20",
        await usdcFixture.position.token()
      );
    });
    it("Correctly mints with permit", async () => {
      // domain separator of USDC mainnet contract at 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
      const domainSeparator = `0x06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335`;
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigest(
        "USD Coin",
        domainSeparator,
        usdcFixture.usdc.address,
        wallet.address,
        usdcFixture.proxy.address,
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
      await usdcFixture.proxy
        .connect(walletSigner)
        .mint(100, underlying.address, 1e10, usdcFixture.position.address, [
          {
            tokenContract: usdcFixture.usdc.address,
            who: usdcFixture.proxy.address,
            amount: ethers.constants.MaxUint256,
            expiration: ethers.constants.MaxUint256,
            r: r,
            s: s,
            v: v,
          },
        ]);
      const trancheValue = await usdcFixture.tranche.balanceOf(wallet.address);
      expect(trancheValue).to.be.eq(100);
    });
  });
});
