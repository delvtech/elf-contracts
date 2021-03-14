import { expect } from "chai";
import { ethers } from "hardhat";
import {
  loadUsdcPoolMainnetFixture,
  UsdcPoolMainnetInterface,
  EthPoolMainnetInterface,
  loadEthPoolMainnetFixture,
  loadPermitTokenPoolMainnetFixture,
  PermitTokenPoolMainnetInterface,
} from "./helpers/deployer";
import { impersonate, stopImpersonating } from "./helpers/impersonate";
import { getDigest } from "./helpers/signatures";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { CodeSizeChecker__factory } from "typechain/factories/CodeSizeChecker__factory";
import { Signer, utils } from "ethers";

describe("UserProxyTests", function () {
  let usdcFixture: UsdcPoolMainnetInterface;

  let proxy: Contract;
  let underlying: Contract;
  let signers: SignerWithAddress[];
  const lots = ethers.utils.parseUnits("1000000", 6);
  const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";

  before(async function () {
    // Get the setup contracts
    usdcFixture = await loadUsdcPoolMainnetFixture();
    ({ proxy } = usdcFixture);

    underlying = await ethers.getContractAt(
      "contracts/libraries/ERC20.sol:ERC20",
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
      usdcFixture.position.address
    );
    // Mint for the first time
    receipt = await receipt.wait();
    console.log("First Mint", receipt.gasUsed.toNumber());
    receipt = await proxy.mint(
      ethers.utils.parseUnits("1", 6),
      underlying.address,
      1e10,
      usdcFixture.position.address
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
        usdcFixture.position.address
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

  describe.only("erc20 Permit mint", async () => {
    let permitFixture: PermitTokenPoolMainnetInterface;
    let users: { user: Signer; address: string }[];
    const tokenHolderAddress = "0x2cc86980e2064d347d878d895ab3f46a8219fcc1";
    before(async function () {
      permitFixture = await loadPermitTokenPoolMainnetFixture();
      users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
        return { user, address: "" };
      });
      await Promise.all(
        users.map(async (userInfo) => {
          const { user } = userInfo;
          userInfo.address = await user.getAddress();
        })
      );
      impersonate(tokenHolderAddress);
      const tokenHolder = await ethers.provider.getSigner(tokenHolderAddress);
      await permitFixture.permitToken
        .connect(tokenHolder)
        .transfer(users[1].address, utils.parseEther("1"));
      underlying = await ethers.getContractAt(
        "contracts/libraries/ERC20.sol:ERC20",
        await permitFixture.position.token()
      );
    });
    it("Correctly transfers with permit", async () => {
      const domainSeparator = await permitFixture.permitToken.DOMAIN_SEPARATOR();
      const nonce = await permitFixture.permitToken.nonces(users[1].address);
      const digest = getDigest(
        domainSeparator,
        users[1].address,
        permitFixture.proxy.address,
        utils.parseEther("1"),
        nonce,
        ethers.BigNumber.from(
          "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        )
      );
      const joinedSig = await users[1].user.signMessage(digest);
      const splitSig = ethers.utils.splitSignature(joinedSig);

      await permitFixture.proxy
        .connect(users[1].user)
        .mintPermit(
          utils.parseEther("1"),
          underlying.address,
          0,
          permitFixture.position.address,
          splitSig.v,
          splitSig.r,
          splitSig.s
        );
    });
  });
});
