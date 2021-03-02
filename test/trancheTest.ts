import { ethers } from "hardhat";

import { bnFloatMultiplier } from "./helpers/math";
import { loadTestTrancheFixture, trancheTestFixture } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime } from "./helpers/time";

import { expect } from "chai";
import { BigNumber, Signer } from "ethers";

const { waffle } = require("hardhat");
const provider = waffle.provider;

describe("Tranche", () => {
  let fixture: trancheTestFixture;
  let user1: Signer;
  let user2: Signer;
  let user1Address: string;
  let user2Address: string;
  let lockDuration = 5000000; //seconds
  let initialBalance = ethers.BigNumber.from("2000000000"); // 2e9

  function subError(amount: BigNumber) {
    // 1 tenth of a bp of error subbed
    return amount.sub(bnFloatMultiplier(amount, 0.00001));
  }

  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts
    fixture = await loadTestTrancheFixture();

    [user1, user2] = await ethers.getSigners();
    user1Address = await user1.getAddress();
    user2Address = await user2.getAddress();

    // Mint for the users
    await fixture.usdc.connect(user1).setBalance(user1Address, 2e9);
    await fixture.usdc.connect(user2).setBalance(user2Address, 2e9);
    // Set approvals on the tranche
    await fixture.usdc.connect(user1).approve(fixture.tranche.address, 2e10);
    await fixture.usdc.connect(user2).approve(fixture.tranche.address, 2e10);
  });
  after(async () => {
    // revert back to initial state after all tests pass
    await restoreSnapshot(provider);
  });
  describe("deposit", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should not allow new deposits after the timeout", async () => {
      advanceTime(provider, lockDuration);
      // Regular deposit fails
      await expect(
        fixture.tranche
          .connect(user1)
          .deposit(initialBalance, await user1.getAddress())
      ).to.be.revertedWith("expired");
      // And prefunded deposit fails
      await expect(
        fixture.tranche
          .connect(user1)
          .prefundedDeposit(await user1.getAddress())
      ).to.be.revertedWith("expired");
    });
    it("should correctly handle deposits with no accrued interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, await user1.getAddress());
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      // check for correct YC balance
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(initialBalance);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(initialBalance);

      // check for correct FYT balance
      expect(await fixture.tranche.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.tranche.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // check that the backing tokens were transferred
      expect(await fixture.usdc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.usdc.balanceOf(user2Address)).to.equal(0);
    });
    it("should correctly handle deposits with accrued interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accululated to 20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      // check for correct YC balance
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(initialBalance);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(initialBalance);

      // check for correct FYT balance.
      // given the same ELF token input, the user should always gain the same FYT output.
      expect(await fixture.tranche.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      // We use a slightly lower ratio allowing for at most 0.001% error
      // The second deposit receive fyt discounted by the 20% intrest earned
      const intrestSubtracted = initialBalance.sub(
        bnFloatMultiplier(initialBalance, 0.20001)
      );
      expect(await fixture.tranche.balanceOf(user2Address)).to.be.least(
        intrestSubtracted
      );
    });
    it("should correctly handle deposits with negative interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accululated to -20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.1)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      // When there's negative intrest fyts are not given a bonus for minting
      expect(fytBalanceU1).to.equal(fytBalanceU2);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(initialBalance);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(initialBalance);
    });
  });
  describe("withdraw", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should correctly handle FYT withdrawals with no accrued interest", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawFyt(fytBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawFyt(fytBalanceU2, user2Address);

      expect(await fixture.usdc.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.equal(
        initialBalance
      );
    });
    it("should correctly handle FYT withdrawals with accrued interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accululated to 20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawFyt(fytBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawFyt(fytBalanceU2, user2Address);

      // We check that the users receive the correct amount of output
      expect(await fixture.usdc.balanceOf(user1Address)).to.be.least(
        subError(initialUnderlying)
      );
      const intrestSubtracted = initialBalance.sub(
        bnFloatMultiplier(initialBalance, 0.2)
      );
      // We check that the user receives the correct output for their smaller deposit
      expect(await fixture.usdc.balanceOf(user2Address)).to.be.least(
        subError(intrestSubtracted)
      );
    });
    it("should correctly handle YC withdrawals with no accrued interest", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawYc(ycBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawYc(ycBalanceU2, user2Address);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);
    });
    it("should correctly handle YC withdrawals with accrued interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accululated to 20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawYc(ycBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawYc(ycBalanceU2, user2Address);

      // given the same backing token input, the users should gain the same YC output
      const userToken = await fixture.usdc.balanceOf(user1Address);
      expect(userToken).to.be.least(
        subError(bnFloatMultiplier(initialBalance, 0.2))
      );
      expect(userToken).to.equal(await fixture.usdc.balanceOf(user2Address));
    });
    it("should correctly handle YC withdrawals with negative interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accululated to -20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawYc(ycBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawYc(ycBalanceU2, user2Address);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);

      // YCs should not be worth any backing tokens if interest is negative
      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(0);
    });
    it("should correctly handle FYT withdrawals with negative interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accululated to -50%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.5)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      expect(fytBalanceU1).to.equal(fytBalanceU2);

      await fixture.tranche
        .connect(user1)
        .withdrawFyt(fytBalanceU1, user1Address);
      // NOTE - This case is the failure race in the case of loss of intrest rates
      const tx = fixture.tranche
        .connect(user2)
        .withdrawFyt(fytBalanceU2, user2Address);
      // The underflow reverts with empty error
      expect(tx).to.be.revertedWith("");

      const backingBalanceU1 = await fixture.usdc.balanceOf(user1Address);

      expect(backingBalanceU1).to.equal(initialBalance);
    });
    it("should correctly handle full withdrawals with no accrued interest - withdraw YC, then FYT", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawYc(ycBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawYc(ycBalanceU2, user2Address);
      await fixture.tranche
        .connect(user1)
        .withdrawFyt(fytBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawFyt(fytBalanceU2, user2Address);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);
      expect(await fixture.usdc.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.tranche.ycSupply()).to.equal(0);
      expect(await fixture.tranche.valueSupplied()).to.equal(0);
      expect(await fixture.elfStub.balanceOf(fixture.tranche.address)).to.equal(
        0
      );
    });
    it("should correctly handle full withdrawals with no accrued interest - withdraw FYT, then YC", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawFyt(fytBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawFyt(fytBalanceU2, user2Address);
      await fixture.tranche
        .connect(user1)
        .withdrawYc(ycBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawYc(ycBalanceU2, user2Address);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);
      expect(await fixture.usdc.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.tranche.ycSupply()).to.equal(0);
      expect(await fixture.tranche.valueSupplied()).to.equal(0);
      expect(await fixture.elfStub.balanceOf(fixture.tranche.address)).to.equal(
        0
      );
    });
    it("should correctly handle full withdrawals with accrued interest -  withdraw YC, then FYT", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accululated to 100%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawYc(ycBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawYc(ycBalanceU2, user2Address);
      await fixture.tranche
        .connect(user1)
        .withdrawFyt(fytBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawFyt(fytBalanceU2, user2Address);

      const intrestAdjusted = bnFloatMultiplier(initialBalance, 1.2);
      expect(await fixture.usdc.balanceOf(user1Address)).to.be.least(
        subError(intrestAdjusted)
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.be.least(
        subError(initialBalance)
      );
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(
        await fixture.yc.balanceOf(user2Address)
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.tranche.ycSupply()).to.equal(0);
      expect(await fixture.tranche.valueSupplied()).to.equal(0);
      // This check is basically that it removes all of the balance except error
      // There's a slight error here which is that total deposits is underlying units
      // not elf but the dif is about 2% and not enough to cause problems
      const totalDeposits = initialBalance.mul(2);
      expect(totalDeposits.sub(subError(totalDeposits))).to.be.least(
        await fixture.elfStub.balanceOf(fixture.tranche.address)
      );
    });
    it("should correctly handle full withdrawals with accrued interest -  withdraw FYT, then YC", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accululated to 100%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawFyt(fytBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawFyt(fytBalanceU2, user2Address);
      await fixture.tranche
        .connect(user1)
        .withdrawYc(ycBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawYc(ycBalanceU2, user2Address);

      const intrestAdjusted = bnFloatMultiplier(initialBalance, 2);
      expect(await fixture.usdc.balanceOf(user1Address)).to.be.least(
        subError(intrestAdjusted)
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.be.least(
        subError(initialBalance)
      );
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(
        await fixture.yc.balanceOf(user2Address)
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.tranche.ycSupply()).to.equal(0);
      expect(await fixture.tranche.valueSupplied()).to.equal(0);
      expect(await fixture.elfStub.balanceOf(fixture.tranche.address)).to.equal(
        0
      );
    });
    it("should prevent withdrawal of FYTs and YCs before the tranche expires ", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      await expect(
        fixture.tranche.connect(user1).withdrawYc(1, user1Address)
      ).to.be.revertedWith("not expired yet");
      await expect(
        fixture.tranche.connect(user1).withdrawFyt(1, user1Address)
      ).to.be.revertedWith("not expired yet");
    });
    it("should prevent withdrawal of more FYTs and YCs than the user has", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      advanceTime(provider, lockDuration);

      const user1FytBalance = await fixture.tranche.balanceOf(user1Address);
      await expect(
        fixture.tranche
          .connect(user1)
          .withdrawYc(initialBalance.add(1), user1Address)
      ).to.be.reverted;
      await expect(
        fixture.tranche
          .connect(user1)
          .withdrawFyt(user1FytBalance.add(1), user1Address)
      ).to.be.reverted;
    });
  });
});
