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
    const usdcWhale = await ethers.provider.getSigner(usdcWhaleAddress);

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
      const balance = (
        await (await fixture.yusdc.balanceOf(fixture.position.address)).mul(
          pricePerFullShare
        )
      ).div(ethers.utils.parseUnits("1", 6));
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

  describe("Funded Reserve Deposit/Withdraw", () => {
    it("should correctly handle deposits and withdrawals", async () => {
      impersonate(usdcWhaleAddress);
      const usdcWhale = await ethers.provider.getSigner(usdcWhaleAddress);
      // A user funds the reserves to enable gas efficient actions
      const initialReserve = 3e11;
      await fixture.usdc
        .connect(usdcWhale)
        .approve(fixture.position.address, 4e11);
      await fixture.position
        .connect(usdcWhale)
        .reserveDeposit(initialReserve + 1);
      let deposit = await yearnDepositSim(fixture, initialReserve);
      let pricePerFullShare = await fixture.yusdc.pricePerShare();

      // Now we try some deposits
      // Note we use less here because the second calc has some rounding error
      // In the first trade the reserve has no wrapped position shares
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e11);
      let userBalance = await fixture.position.balanceOf(users[1].address);
      let shareAmount = BigNumber.from(1e11).mul(1e6).div(pricePerFullShare);
      expect(userBalance).to.be.at.least(subError(shareAmount));
      const shareReserve = await fixture.position.reserveShares();
      expect(shareReserve).to.be.eq(deposit);
      expect(await fixture.position.reserveUnderlying()).to.be.eq(0);

      // The second is fully fillable from the reserve's wrapped position shares
      deposit = BigNumber.from(2e11).mul(1e6).div(pricePerFullShare);
      await fixture.position
        .connect(users[2].user)
        .deposit(users[2].address, 2e11);
      userBalance = await fixture.position.balanceOf(users[2].address);
      shareAmount = BigNumber.from(2e11).mul(1e6).div(pricePerFullShare);
      expect(userBalance).to.be.at.least(subError(shareAmount));
      expect(await fixture.position.reserveShares()).to.be.eq(
        shareReserve.sub(deposit)
      );
      expect(await fixture.position.reserveUnderlying()).to.be.eq(2e11);

      // The third consumes the remaining requiring switchover
      deposit = await yearnDepositSim(fixture, initialReserve + 1);
      await fixture.usdc.connect(users[4].user).transfer(users[1].address, 1);
      // Note we have to add 1 unit to this transfer to cause the right behavior
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e11 + 1);
      userBalance = await fixture.position.balanceOf(users[1].address);
      shareAmount = BigNumber.from(2e11).mul(1e6).div(pricePerFullShare);
      expect(userBalance).to.be.at.least(subError(shareAmount));
      expect(await fixture.position.reserveShares()).to.be.at.least(
        subError(deposit)
      );
      expect(await fixture.position.reserveUnderlying()).to.be.eq(0);

      // Final deposit should be preformed without the reserve
      await fixture.position
        .connect(users[3].user)
        .deposit(users[3].address, 6e11);
      userBalance = await fixture.position.balanceOf(users[3].address);
      shareAmount = BigNumber.from(6e11).mul(1e6).div(pricePerFullShare);
      expect(userBalance).to.be.at.least(subError(shareAmount));
      expect(await fixture.position.reserveShares()).to.be.at.least(
        subError(deposit)
      );
      expect(await fixture.position.reserveUnderlying()).to.be.eq(0);

      // Test withdraws
      const toWithdraw = ethers.BigNumber.from("1000000"); // 1 usdc
      const user1Balance = await fixture.position.balanceOf(users[1].address);
      pricePerFullShare = await fixture.yusdc.pricePerShare();
      const withdrawUsdc = toWithdraw
        .mul(pricePerFullShare)
        .div(ethers.utils.parseUnits("1", 6));

      let usdcBalance = await yearnWithdrawSim(fixture, deposit);
      await fixture.position
        .connect(users[1].user)
        .withdraw(users[1].address, toWithdraw, 0);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(
        user1Balance.sub(toWithdraw)
      );
      expect(await fixture.usdc.balanceOf(users[1].address)).to.equal(
        withdrawUsdc
      );
      expect(await fixture.position.reserveShares()).to.be.eq(0);
      // The extra unit is from rounding error in the contract's favor
      expect(await fixture.position.reserveUnderlying()).to.be.at.least(
        subError(usdcBalance)
      );

      const shareBalanceU1 = await fixture.position.balanceOf(users[1].address);
      let newWithdraw = await yearnWithdrawSim(fixture, shareBalanceU1);
      await fixture.position
        .connect(users[1].user)
        .withdraw(users[1].address, shareBalanceU1, 0);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(0);
      expect(await fixture.position.reserveShares()).to.be.eq(shareBalanceU1);
      expect(await fixture.position.reserveUnderlying()).to.be.eq(
        usdcBalance.sub(newWithdraw)
      );
      // We record the current share balance
      usdcBalance = usdcBalance.add(1).sub(newWithdraw);

      // This withdraw requires resetting the reserves
      const shareBalanceU2 = await fixture.position.balanceOf(users[2].address);
      newWithdraw = await yearnWithdrawSim(fixture, shareBalanceU2);
      await fixture.position
        .connect(users[2].user)
        .withdraw(users[2].address, shareBalanceU2, 0);
      expect(await fixture.position.balanceOf(users[2].address)).to.equal(0);
      expect(await fixture.position.reserveShares()).to.be.eq(0);
      expect(await fixture.position.reserveUnderlying()).to.be.eq(
        initialReserve + 1
      );

      // This withdraw cannot use the reserves so doesn't change them
      const shareBalanceU3 = await fixture.position.balanceOf(users[3].address);
      await fixture.position
        .connect(users[3].user)
        .withdraw(users[3].address, shareBalanceU3, 0);
      expect(await fixture.position.balanceOf(users[3].address)).to.equal(0);
      expect(await fixture.position.reserveShares()).to.be.eq(0);
      expect(await fixture.position.reserveUnderlying()).to.be.eq(
        initialReserve + 1
      );

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
});
