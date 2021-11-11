import { expect } from "chai";
import { Signer, BigNumber, BigNumberish } from "ethers";
import { ethers, waffle } from "hardhat";

import {
  loadUsdcPoolMainnetFixture,
  UsdcPoolMainnetInterface,
} from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { impersonate, stopImpersonating } from "./helpers/impersonate";
import { subError } from "./helpers/math";

const { provider } = waffle;

describe("USDCPool-Mainnet", () => {
  let users: { user: Signer; address: string }[];
  let fixture: UsdcPoolMainnetInterface;
  // address of a large usdc holder to impersonate. 69 million usdc as of block 11860000
  const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";
  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts
    fixture = await loadUsdcPoolMainnetFixture();

    // begin to populate the user array by assigning each index a signer
    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return { user, address: "" };
    });

    // finish populating the user array by assigning each index a signer address
    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    impersonate(usdcWhaleAddress);
    const usdcWhale = ethers.provider.getSigner(usdcWhaleAddress);

    await fixture.usdc.connect(usdcWhale).transfer(users[1].address, 2e11); // 200k usdc
    await fixture.usdc.connect(usdcWhale).transfer(users[2].address, 2e11); // 200k usdc
    await fixture.usdc.connect(usdcWhale).transfer(users[3].address, 6e11); // 600k usdc
    await fixture.usdc.connect(usdcWhale).transfer(users[4].address, 10e11); // 1000k usdc

    stopImpersonating(usdcWhaleAddress);

    await fixture.usdc
      .connect(users[1].user)
      .approve(fixture.position.address, 10e11); // 200k usdc
    await fixture.usdc
      .connect(users[2].user)
      .approve(fixture.position.address, 10e11); // 200k usdc
    await fixture.usdc
      .connect(users[3].user)
      .approve(fixture.position.address, 10e11); // 600k usdc
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

  describe("deposit + withdraw", () => {
    it("should correctly handle deposits and withdrawals", async () => {
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e11);
      await fixture.position
        .connect(users[2].user)
        .deposit(users[2].address, 2e11);
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e11);
      await fixture.position
        .connect(users[3].user)
        .deposit(users[3].address, 6e11);

      let pricePerFullShare = await fixture.yusdc.pricePerShare();
      const balance = (await fixture.yusdc.balanceOf(fixture.position.address))
        .mul(pricePerFullShare)
        .div(ethers.utils.parseUnits("1", 6));
      // Allows a 0.01% conversion error
      expect(balance).to.be.at.least(subError(ethers.BigNumber.from(1e11)));

      /* At this point:
       *         deposited     held
       * User 1: 20,000 USDC | 0 USDC
       * user 2: 20,000 USDC | 0 USDC
       * User 3: 60,000 USDC | 0 USDC
       */

      // Test a transfer
      let user1Balance = await fixture.position.balanceOf(users[1].address);
      const user3Balance = await fixture.position.balanceOf(users[3].address);
      await fixture.position
        .connect(users[3].user)
        .transfer(users[1].address, user3Balance.div(ethers.BigNumber.from(2)));
      expect(
        (await fixture.position.balanceOf(users[1].address)).add(
          await fixture.position.balanceOf(users[3].address)
        )
      ).to.equal(user1Balance.add(user3Balance));

      /* At this point:
       *         deposited     held
       * User 1: 50,000 USDC | 0 USDC
       * user 2: 20,000 USDC | 0 USDC
       * User 3: 30,000 USDC | 0 USDC
       */

      // Test withdraws

      const toWithdraw = ethers.BigNumber.from("1000000"); // 1 usdc
      user1Balance = await fixture.position.balanceOf(users[1].address);
      pricePerFullShare = await fixture.yusdc.pricePerShare();
      const withdrawUsdc = toWithdraw
        .mul(pricePerFullShare)
        .div(ethers.utils.parseUnits("1", 6));

      await fixture.position
        .connect(users[1].user)
        .withdraw(users[1].address, toWithdraw, 0);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(
        user1Balance.sub(toWithdraw)
      );
      expect(await fixture.usdc.balanceOf(users[1].address)).to.equal(
        withdrawUsdc
      );

      /* At this point:
       *         deposited     held
       * User 1: 49,999 USDC | 1 USDC
       * user 2: 20,000 USDC | 0 USDC
       * User 3: 30,000 USDC | 0 USDC
       */

      const shareBalanceU1 = await fixture.position.balanceOf(users[1].address);
      await fixture.position
        .connect(users[1].user)
        .withdraw(users[1].address, shareBalanceU1, 0);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(0);

      const shareBalanceU2 = await fixture.position.balanceOf(users[2].address);
      await fixture.position
        .connect(users[2].user)
        .withdraw(users[2].address, shareBalanceU2, 0);
      expect(await fixture.position.balanceOf(users[2].address)).to.equal(0);

      const shareBalanceU3 = await fixture.position.balanceOf(users[3].address);
      await fixture.position
        .connect(users[3].user)
        .withdraw(users[3].address, shareBalanceU3, 0);
      expect(await fixture.position.balanceOf(users[3].address)).to.equal(0);

      /* At this point:
       *         deposited     held
       * User 1: 0 USDC      | 50,000 USDC
       * user 2: 0 USDC      | 20,000 USDC
       * User 3: 0 USDC      | 30,000 USDC
       */

      const finalWethBalanceU1 = await fixture.usdc.balanceOf(users[1].address);
      const finalWethBalanceU2 = await fixture.usdc.balanceOf(users[2].address);
      const finalWethBalanceU3 = await fixture.usdc.balanceOf(users[3].address);
      expect(
        finalWethBalanceU1
          .add(finalWethBalanceU2)
          .add(finalWethBalanceU3)
          .add(ethers.BigNumber.from("5"))
      ).to.be.at.least(subError(BigNumber.from("1000000000000")));
    });
  });

  describe("balanceOfUnderlying", () => {
    it("should return the correct underlying balance", async () => {
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e11);
      // Allow for 0.01% of slippage
      expect(
        await fixture.position.balanceOfUnderlying(users[1].address)
      ).to.be.at.least(99999000000);
    });
  });

  async function yearnDepositSim(
    fixture: UsdcPoolMainnetInterface,
    amount: BigNumberish
  ) {
    const yearnTotalSupply = await fixture.yusdc.totalSupply();
    const yearnTotalAssets = await fixture.yusdc.totalAssets();
    return yearnTotalSupply.mul(amount).div(yearnTotalAssets);
  }

  async function yearnWithdrawSim(
    fixture: UsdcPoolMainnetInterface,
    amount: BigNumberish
  ) {
    const yearnTotalSupply = await fixture.yusdc.totalSupply();
    const yearnTotalAssets = await fixture.yusdc.totalAssets();
    return yearnTotalAssets.mul(amount).div(yearnTotalSupply);
  }
});
