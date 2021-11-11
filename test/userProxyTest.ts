import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { expect } from "chai";
import { MockProvider } from "ethereum-waffle";
import { ecsign } from "ethereumjs-util";
import { Contract, Signer, utils } from "ethers";
import { ethers, waffle } from "hardhat";
import { ERC20Permit } from "typechain/ERC20Permit";
import { CodeSizeChecker__factory } from "typechain/factories/CodeSizeChecker__factory";
import { ERC20Permit__factory } from "typechain/factories/ERC20Permit__factory";
import { IWETH__factory } from "typechain/factories/IWETH__factory";
import { TestEthSender__factory } from "typechain/factories/TestEthSender__factory";
import { IWETH } from "typechain/IWETH";
import {
  EthPoolMainnetInterface,
  loadEthPoolMainnetFixture,
  loadUsdcPoolMainnetFixture,
  UsdcPoolMainnetInterface,
} from "./helpers/deployer";
import { impersonate } from "./helpers/impersonate";
import { getDigest } from "./helpers/signatures";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime } from "./helpers/time";

const { provider } = waffle;

describe("UserProxyTests", function () {
  let usdcFixture: UsdcPoolMainnetInterface;

  let proxy: Contract;
  let underlying: ERC20Permit;
  let signers: SignerWithAddress[];
  const lots = ethers.utils.parseUnits("1000000", 6);
  const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

  before(async function () {
    await createSnapshot(provider);
    // Get the setup contracts
    usdcFixture = await loadUsdcPoolMainnetFixture();
    ({ proxy } = usdcFixture);
    const underlyingAddress = await usdcFixture.position.token();
    impersonate(usdcWhaleAddress);
    const usdcWhale = ethers.provider.getSigner(usdcWhaleAddress);
    // Get the signers
    signers = await ethers.getSigners();
    underlying = ERC20Permit__factory.connect(underlyingAddress, signers[0]);
    // mint to the user 0
    await underlying.connect(usdcWhale).transfer(signers[0].address, lots);
    // mint to the user 1
    await underlying.connect(usdcWhale).transfer(signers[1].address, lots);

    // Make an initial deposit in the aypool contract
    // This prevents a div by zero reversion in several cases
    await usdcFixture.usdc.connect(usdcWhale).transfer(signers[0].address, 100);
    await usdcFixture.usdc.approve(usdcFixture.yusdc.address, 100);
    await usdcFixture.yusdc.deposit(100, signers[0].address);
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
    receipt = await proxy.mint(
      ethers.utils.parseUnits("1", 6),
      underlying.address,
      1e10,
      usdcFixture.position.address,
      []
    );
    receipt = await receipt.wait();
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
  });

  it("Blocks Weth withdraw function when using USDC", async function () {
    const tx = proxy.withdrawWeth(
      1e10,
      usdcFixture.position.address,
      ethers.BigNumber.from(utils.parseEther("1")),
      ethers.BigNumber.from(utils.parseEther("1")),
      []
    );
    await expect(tx).to.be.revertedWith("Non weth token");
  });

  describe("Deprecation function", async () => {
    it("Blocks deprecation by non owners", async () => {
      const tx = proxy.connect(signers[1]).deprecate();
      await expect(tx).to.be.revertedWith("Sender not owner");
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
    let weth: IWETH;
    let users: { user: Signer; address: string }[];
    let expiration: number;
    let yieldToken: Contract;

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
      expiration = (await wethFixture.tranche.unlockTimestamp()).toNumber();
      const yieldTokenAddress = await wethFixture.tranche.interestToken();
      yieldToken = ERC20Permit__factory.connect(yieldTokenAddress, signers[0]);
      weth = IWETH__factory.connect(wethAddress, signers[0]);
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
      expect(await yieldToken.balanceOf(users[1].address)).to.be.eq(
        ethers.BigNumber.from(utils.parseEther("1"))
      );
    });

    it("Correctly redeems weth pt + yt for eth", async () => {
      // Mint tokens for this test
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
      expect(await wethFixture.tranche.balanceOf(users[1].address)).to.be.eq(
        ethers.BigNumber.from(utils.parseEther("1"))
      );
      expect(await yieldToken.balanceOf(users[1].address)).to.be.eq(
        ethers.BigNumber.from(utils.parseEther("1"))
      );

      // Make the next timestamp be after expiration
      advanceTime(provider, expiration + 1);
      // We don't have
      const yearnAddr = await wethFixture.position.vault();
      const abi = ["function totalAssets() view returns(uint256)"];
      const yearn = new ethers.Contract(yearnAddr, abi, provider);
      const assets = await yearn.connect(users[0].user).totalAssets();

      // Sim some interest accrual
      weth.deposit({ value: assets.div(10) });
      weth.transfer(await wethFixture.position.vault(), assets.div(10));

      // In normal operation we would use permit signatures to get approvals
      // but in this case we pre-approve
      await wethFixture.tranche
        .connect(users[1].user)
        .approve(wethFixture.proxy.address, ethers.constants.MaxUint256);
      await yieldToken
        .connect(users[1].user)
        .approve(wethFixture.proxy.address, ethers.constants.MaxUint256);

      // Try to withdraw principal tokens
      const priorBalance = await provider.getBalance(users[1].address);
      const oneGWie = ethers.utils.parseUnits("1", "gwei");

      let tx = await (
        await wethFixture.proxy
          .connect(users[1].user)
          .withdrawWeth(
            1e10,
            wethFixture.position.address,
            ethers.BigNumber.from(utils.parseEther("1")),
            0,
            [],
            {
              gasPrice: oneGWie,
            }
          )
      ).wait();
      const postBalance = await provider.getBalance(users[1].address);
      let expectedDifferential = ethers.utils
        .parseEther("1")
        .sub(oneGWie.mul(tx.gasUsed));
      expect(postBalance.sub(priorBalance)).to.be.eq(expectedDifferential);

      // Try withdrawing some interest tokens
      tx = await (
        await wethFixture.proxy
          .connect(users[1].user)
          .withdrawWeth(
            1e10,
            wethFixture.position.address,
            0,
            ethers.BigNumber.from(utils.parseEther("1")),
            [],
            {
              gasPrice: oneGWie,
            }
          )
      ).wait();
      const nextBalance = await provider.getBalance(users[1].address);
      expectedDifferential = ethers.utils
        .parseEther("0.1")
        .sub(oneGWie.mul(tx.gasUsed));
      // There's a possibility of rounding error of at most 1/1,000,000
      expectedDifferential = expectedDifferential.sub(
        expectedDifferential.div(1000000)
      );

      expect(nextBalance.sub(postBalance)).to.be.at.least(expectedDifferential);
    });
    it("Blocks weth redemption when both assets are 0", async () => {
      const tx = wethFixture.proxy
        .connect(users[1].user)
        .withdrawWeth(1e10, wethFixture.position.address, 0, 0, []);
      await expect(tx).to.be.revertedWith("Invalid withdraw");
    });
    it("Blocks non weth incoming eth transfers", async () => {
      const senderFactory = new TestEthSender__factory(users[0].user);
      const sender = await senderFactory.deploy();
      const tx = sender.sendEth(wethFixture.proxy.address, { value: 1 });
      await expect(tx).to.be.revertedWith("");
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
      const tokenHolder = ethers.provider.getSigner(usdcWhaleAddress);
      await usdcFixture.usdc.connect(tokenHolder).transfer(wallet.address, 100);
      const underlyingAddress = await usdcFixture.position.token();
      underlying = ERC20Permit__factory.connect(underlyingAddress, signers[0]);
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
      const walletSigner = ethers.provider.getSigner(wallet.address);
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
