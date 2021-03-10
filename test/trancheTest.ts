import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import { loadTestTrancheFixture, TrancheTestFixture } from "./helpers/deployer";
import { bnFloatMultiplier, subError } from "./helpers/math";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime, getCurrentTimestamp } from "./helpers/time";

const { provider } = waffle;

describe("Tranche", () => {
  let fixture: TrancheTestFixture;
  let user1: Signer;
  let user2: Signer;
  let user1Address: string;
  let user2Address: string;
  let expiration: number;
  const initialBalance = ethers.BigNumber.from("2000000000"); // 2e9

  before(async () => {
    const time = await getCurrentTimestamp(provider);
    expiration = 1e10 - time;
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
      advanceTime(provider, expiration);
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
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, await user1.getAddress());
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      // check for correct Interest Token balance
      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.interestToken.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // check for correct Principal Token balance
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
      const initialUnderlying = await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to 20%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      // check for correct Interest Token balance
      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.interestToken.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // check for correct Principal Token balance.
      // given the same Wrapped position token input, the user should always gain the same Principal Token output.
      expect(await fixture.tranche.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      // We use a slightly lower ratio allowing for at most 0.001% error
      // The second deposit receive Principal Token discounted by the 20% interest earned
      const interestSubtracted = initialBalance.sub(
        bnFloatMultiplier(initialBalance, 0.20001)
      );
      expect(await fixture.tranche.balanceOf(user2Address)).to.be.least(
        interestSubtracted
      );
    });
    it("should correctly handle deposits with negative interest", async () => {
      const initialUnderlying = await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to -20%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.1)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      // When there's negative interest principals are not given a bonus for minting
      expect(principalBalanceU1).to.equal(principalBalanceU2);

      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.interestToken.balanceOf(user2Address)).to.equal(
        initialBalance
      );
    });
  });
  describe("withdraw", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should correctly handle Principal Token withdrawals with no accrued interest", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawPrincipal(principalBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawPrincipal(principalBalanceU2, user2Address);

      expect(await fixture.usdc.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.equal(
        initialBalance
      );
    });
    it("should correctly handle Principal Token withdrawals with accrued interest", async () => {
      const initialUnderlying = await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to 20%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawPrincipal(principalBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawPrincipal(principalBalanceU2, user2Address);

      // We check that the users receive the correct amount of output
      expect(await fixture.usdc.balanceOf(user1Address)).to.be.least(
        subError(initialUnderlying)
      );
      const interestSubtracted = initialBalance.sub(
        bnFloatMultiplier(initialBalance, 0.2)
      );
      // We check that the user receives the correct output for their smaller deposit
      expect(await fixture.usdc.balanceOf(user2Address)).to.be.least(
        subError(interestSubtracted)
      );
    });
    it("should correctly handle Interest Token withdrawals with no accrued interest", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const interestTokenBalanceU1 = await fixture.interestToken.balanceOf(
        user1Address
      );
      const interestTokenBalanceU2 = await fixture.interestToken.balanceOf(
        user2Address
      );

      await fixture.tranche
        .connect(user1)
        .withdrawInterest(interestTokenBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawInterest(interestTokenBalanceU2, user2Address);

      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.interestToken.balanceOf(user2Address)).to.equal(0);
    });
    it("should correctly handle Interest Token withdrawals with accrued interest", async () => {
      const initialUnderlying = await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to 20%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const interestTokenBalanceU1 = await fixture.interestToken.balanceOf(
        user1Address
      );
      const interestTokenBalanceU2 = await fixture.interestToken.balanceOf(
        user2Address
      );

      await fixture.tranche
        .connect(user1)
        .withdrawInterest(interestTokenBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawInterest(interestTokenBalanceU2, user2Address);

      // given the same backing token input, the users should gain the same Interest Token output
      const userToken = await fixture.usdc.balanceOf(user1Address);
      expect(userToken).to.be.least(
        subError(bnFloatMultiplier(initialBalance, 0.2))
      );
      expect(userToken).to.equal(await fixture.usdc.balanceOf(user2Address));
    });
    it("should correctly handle Interest Token withdrawals with negative interest", async () => {
      const initialUnderlying = await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to -20%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const interestTokenBalanceU1 = await fixture.interestToken.balanceOf(
        user1Address
      );
      const interestTokenBalanceU2 = await fixture.interestToken.balanceOf(
        user2Address
      );

      await fixture.tranche
        .connect(user1)
        .withdrawInterest(interestTokenBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawInterest(interestTokenBalanceU2, user2Address);

      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.interestToken.balanceOf(user2Address)).to.equal(0);

      // Interest Tokens should not be worth any backing tokens if interest is negative
      expect(await fixture.positionStub.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.positionStub.balanceOf(user2Address)).to.equal(0);
    });
    it("should correctly handle Principal Token withdrawals with negative interest", async () => {
      const initialUnderlying = await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to -50%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.5)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      expect(principalBalanceU1).to.equal(principalBalanceU2);

      await fixture.tranche
        .connect(user1)
        .withdrawPrincipal(principalBalanceU1, user1Address);
      // NOTE - This case is the failure race in the case of loss of interest rates
      const tx = fixture.tranche
        .connect(user2)
        .withdrawPrincipal(principalBalanceU2, user2Address);
      // The underflow reverts with empty error
      expect(tx).to.be.revertedWith("");

      const backingBalanceU1 = await fixture.usdc.balanceOf(user1Address);

      expect(backingBalanceU1).to.equal(initialBalance);
    });
    it("should correctly handle full withdrawals with no accrued interest - withdraw Interest Token, then Principal Token", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const interestTokenBalanceU1 = await fixture.interestToken.balanceOf(
        user1Address
      );
      const interestTokenBalanceU2 = await fixture.interestToken.balanceOf(
        user2Address
      );
      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawInterest(interestTokenBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawInterest(interestTokenBalanceU2, user2Address);
      await fixture.tranche
        .connect(user1)
        .withdrawPrincipal(principalBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawPrincipal(principalBalanceU2, user2Address);

      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.interestToken.balanceOf(user2Address)).to.equal(0);
      expect(await fixture.usdc.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // ensure that all Principal Tokens and Interest Tokens were burned and the tranche balance is 0
      expect(await fixture.tranche.interestSupply()).to.equal(0);
      expect(await fixture.tranche.valueSupplied()).to.equal(0);
      expect(
        await fixture.positionStub.balanceOf(fixture.tranche.address)
      ).to.equal(0);
    });
    it("should correctly handle full withdrawals with no accrued interest - withdraw Principal Token, then Interest Token", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const interestTokenBalanceU1 = await fixture.interestToken.balanceOf(
        user1Address
      );
      const interestTokenBalanceU2 = await fixture.interestToken.balanceOf(
        user2Address
      );
      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawPrincipal(principalBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawPrincipal(principalBalanceU2, user2Address);
      await fixture.tranche
        .connect(user1)
        .withdrawInterest(interestTokenBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawInterest(interestTokenBalanceU2, user2Address);

      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.interestToken.balanceOf(user2Address)).to.equal(0);
      expect(await fixture.usdc.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // ensure that all Principal Tokens and Interest Tokens were burned and the tranche balance is 0
      expect(await fixture.tranche.interestSupply()).to.equal(0);
      expect(await fixture.tranche.valueSupplied()).to.equal(0);
      expect(
        await fixture.positionStub.balanceOf(fixture.tranche.address)
      ).to.equal(0);
    });
    it("should correctly handle full withdrawals with accrued interest -  withdraw Interest Token, then Principal Token", async () => {
      const initialUnderlying = await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to 100%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const interestTokenBalanceU1 = await fixture.interestToken.balanceOf(
        user1Address
      );
      const interestTokenBalanceU2 = await fixture.interestToken.balanceOf(
        user2Address
      );
      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawInterest(interestTokenBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawInterest(interestTokenBalanceU2, user2Address);
      await fixture.tranche
        .connect(user1)
        .withdrawPrincipal(principalBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawPrincipal(principalBalanceU2, user2Address);

      const interestAdjusted = bnFloatMultiplier(initialBalance, 1.2);
      expect(await fixture.usdc.balanceOf(user1Address)).to.be.least(
        subError(interestAdjusted)
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.be.least(
        subError(initialBalance)
      );
      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(
        await fixture.interestToken.balanceOf(user2Address)
      );

      // ensure that all Principal Tokens and Interest Tokens were burned and the tranche balance is 0
      expect(await fixture.tranche.interestSupply()).to.equal(0);
      expect(await fixture.tranche.valueSupplied()).to.equal(0);
      // This check is basically that it removes all of the balance except error
      // There's a slight error here which is that total deposits is underlying units
      // not wrapped position units but the dif is about 2% and not enough to cause problems
      const totalDeposits = initialBalance.mul(2);
      expect(totalDeposits.sub(subError(totalDeposits))).to.be.least(
        await fixture.positionStub.balanceOf(fixture.tranche.address)
      );
    });
    it("should correctly handle full withdrawals with accrued interest -  withdraw Principal Token, then Interest Token", async () => {
      const initialUnderlying = await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to 100%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 2)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      advanceTime(provider, expiration);

      const interestTokenBalanceU1 = await fixture.interestToken.balanceOf(
        user1Address
      );
      const interestTokenBalanceU2 = await fixture.interestToken.balanceOf(
        user2Address
      );
      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche
        .connect(user1)
        .withdrawPrincipal(principalBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawPrincipal(principalBalanceU2, user2Address);
      await fixture.tranche
        .connect(user1)
        .withdrawInterest(interestTokenBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawInterest(interestTokenBalanceU2, user2Address);

      const interestAdjusted = bnFloatMultiplier(initialBalance, 2);
      expect(await fixture.usdc.balanceOf(user1Address)).to.be.least(
        subError(interestAdjusted)
      );
      expect(await fixture.usdc.balanceOf(user2Address)).to.be.least(
        subError(initialBalance)
      );
      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(
        await fixture.interestToken.balanceOf(user2Address)
      );

      // ensure that all Principal Tokens and Interest Tokens were burned and the tranche balance is 0
      expect(await fixture.tranche.interestSupply()).to.equal(0);
      expect(await fixture.tranche.valueSupplied()).to.equal(0);
      expect(
        await fixture.positionStub.balanceOf(fixture.tranche.address)
      ).to.equal(0);
    });
    it("should prevent withdrawal of Principal Tokens and Interest Tokens before the tranche expires ", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      await expect(
        fixture.tranche.connect(user1).withdrawInterest(1, user1Address)
      ).to.be.revertedWith("not expired");
      await expect(
        fixture.tranche.connect(user1).withdrawPrincipal(1, user1Address)
      ).to.be.revertedWith("not expired");
    });
    it("should prevent withdrawal of more Principal Tokens and Interest Tokens than the user has", async () => {
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      advanceTime(provider, expiration);

      const user1PrincipalTokenBalance = await fixture.tranche.balanceOf(
        user1Address
      );
      await expect(
        fixture.tranche
          .connect(user1)
          .withdrawInterest(initialBalance.add(1), user1Address)
      ).to.be.reverted;
      await expect(
        fixture.tranche
          .connect(user1)
          .withdrawPrincipal(user1PrincipalTokenBalance.add(1), user1Address)
      ).to.be.reverted;
    });
  });
});
