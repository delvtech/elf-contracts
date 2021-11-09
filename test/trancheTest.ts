import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import { loadTestTrancheFixture, TrancheTestFixture } from "./helpers/deployer";
import { bnFloatMultiplier, subError } from "./helpers/math";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime, getCurrentTimestamp } from "./helpers/time";
import { getPermitSignature } from "./helpers/signatures";
import { ERC20Permit } from "typechain/ERC20Permit";

const { provider } = waffle;

describe("Tranche", () => {
  let fixture: TrancheTestFixture;
  let user1: Signer;
  let user2: Signer;
  let user1Address: string;
  let user2Address: string;
  let expiration: number;
  const initialBalance = ethers.BigNumber.from("2000000000"); // 2e9
  const forty_eight_hours = 172800;
  const errorTolerance = 0.0000001;

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
    await fixture.usdc.connect(user1).setBalance(user1Address, initialBalance);
    await fixture.usdc.connect(user2).setBalance(user2Address, initialBalance);
    // Set approvals on the tranche
    await fixture.usdc.connect(user1).approve(fixture.tranche.address, 2e10);
    await fixture.usdc.connect(user2).approve(fixture.tranche.address, 2e10);
  });
  after(async () => {
    // revert back to initial state after all tests pass
    await restoreSnapshot(provider);
  });
  describe("permit", () => {
    it("pt allows valid permit call", async () => {
      const erc20Tranche = fixture.tranche as ERC20Permit;
      const signerAddress = await user1.getAddress();
      const spenderAddress = await user2.getAddress();
      const sig = await getPermitSignature(
        erc20Tranche,
        signerAddress,
        spenderAddress,
        ethers.constants.MaxUint256,
        "1"
      );

      await fixture.tranche
        .connect(user2)
        .permit(
          signerAddress,
          spenderAddress,
          ethers.constants.MaxUint256,
          ethers.constants.MaxUint256,
          sig.v,
          sig.r,
          sig.s
        );
      expect(
        await fixture.tranche.allowance(signerAddress, spenderAddress)
      ).to.be.eq(ethers.constants.MaxUint256);
    });
    it("yt allows valid permit call", async () => {
      const erc20YT = fixture.interestToken as ERC20Permit;
      const signerAddress = await user1.getAddress();
      const spenderAddress = await user2.getAddress();
      const sig = await getPermitSignature(
        erc20YT,
        signerAddress,
        spenderAddress,
        ethers.constants.MaxUint256,
        "1"
      );

      await fixture.interestToken
        .connect(user2)
        .permit(
          signerAddress,
          spenderAddress,
          ethers.constants.MaxUint256,
          ethers.constants.MaxUint256,
          sig.v,
          sig.r,
          sig.s
        );
      expect(
        await fixture.interestToken.allowance(signerAddress, spenderAddress)
      ).to.be.eq(ethers.constants.MaxUint256);
    });
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
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

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
    it("should block deposits with negative interest", async () => {
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to -20%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.1)
      );

      const tx = fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);
      await expect(tx).to.be.revertedWith("E:NEG_INT");

      advanceTime(provider, expiration);

      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);

      // When there's negative interest principals are not given a bonus for minting
      expect(principalBalanceU1).to.equal(initialBalance);

      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(
        initialBalance
      );
    });
    it("Correctly deposits at 3 times", async () => {
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche.deposit(1e8, user1Address);
      expect(await fixture.tranche.balanceOf(user1Address)).to.be.eq(1e8);
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.5)
      );
      await fixture.tranche.connect(user2).deposit(1e8, user2Address);
      expect(await fixture.tranche.balanceOf(user2Address)).to.be.eq(49999850);
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.8)
      );
      await fixture.tranche.deposit(1e8, user1Address);
      expect(await fixture.tranche.balanceOf(user1Address)).to.be.eq(
        1e8 + 24999835
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
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

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
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

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
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      // set pool interest accumulated to -20%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.2)
      );

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
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to 10%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.1)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      // set pool interest accumulated to -50%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.5)
      );

      advanceTime(provider, expiration);

      await fixture.tranche.hitSpeedbump();

      advanceTime(provider, expiration + forty_eight_hours);

      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      expect(principalBalanceU1).to.equal(initialBalance);
      // We allow some rounding error
      expect(principalBalanceU2).to.be.least(
        bnFloatMultiplier(initialBalance, 0.9 - errorTolerance)
      );
      expect(principalBalanceU2).to.be.most(
        bnFloatMultiplier(initialBalance, 0.9 + errorTolerance)
      );

      const totalPrincipal = principalBalanceU1.add(principalBalanceU2);
      const contractHoldings1 = await fixture.positionStub.balanceOfUnderlying(
        fixture.tranche.address
      );
      await fixture.tranche
        .connect(user1)
        .withdrawPrincipal(principalBalanceU1, user1Address);
      const contractHoldings2 = await fixture.positionStub.balanceOfUnderlying(
        fixture.tranche.address
      );
      await fixture.tranche
        .connect(user2)
        .withdrawPrincipal(principalBalanceU2, user2Address);

      const backingBalanceU1 = await fixture.usdc.balanceOf(user1Address);
      const backingBalanceU2 = await fixture.usdc.balanceOf(user2Address);

      // Tries first one
      const u1Expected = contractHoldings1
        .mul(initialBalance)
        .div(totalPrincipal);
      // For small rounding errors
      expect(backingBalanceU1).to.be.least(
        bnFloatMultiplier(u1Expected, 1 - errorTolerance)
      );
      expect(backingBalanceU1).to.be.most(
        bnFloatMultiplier(u1Expected, 1 + errorTolerance)
      );

      // In this case the multiplication and division cancel out
      const u2Expected = contractHoldings2;
      expect(backingBalanceU2).to.be.least(
        bnFloatMultiplier(u2Expected, 1 - errorTolerance)
      );
      expect(backingBalanceU2).to.be.most(
        bnFloatMultiplier(u2Expected, 1 + errorTolerance)
      );
    });

    it("should correctly handle Principal Token withdrawals with falsely reported negative interest", async () => {
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

      // Deposit across interest rates
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to 10%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.1)
      );

      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      // Check that the deposits work as expected
      const principalBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const principalBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      expect(principalBalanceU1).to.equal(initialBalance);
      // We allow some rounding error
      expect(principalBalanceU2).to.be.least(
        bnFloatMultiplier(initialBalance, 0.9 - errorTolerance)
      );
      expect(principalBalanceU2).to.be.most(
        bnFloatMultiplier(initialBalance, 0.9 + errorTolerance)
      );

      // set pool interest accumulated to -50%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.5)
      );

      // Move past tranche expiration
      advanceTime(provider, expiration);

      // Falsely report negative interest
      await fixture.tranche.hitSpeedbump();

      // Reset to properly reported interest
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.1)
      );

      // Do withdraws
      await fixture.tranche
        .connect(user1)
        .withdrawPrincipal(principalBalanceU1, user1Address);
      await fixture.tranche
        .connect(user2)
        .withdrawPrincipal(principalBalanceU2, user2Address);

      // Load the usdc balance after
      const backingBalanceU1 = await fixture.usdc.balanceOf(user1Address);
      const backingBalanceU2 = await fixture.usdc.balanceOf(user2Address);

      // Check that we get back within rounding error of the correct amounts
      expect(backingBalanceU1).to.be.least(
        bnFloatMultiplier(initialBalance, 1 - errorTolerance)
      );
      expect(backingBalanceU1).to.be.most(
        bnFloatMultiplier(initialBalance, 1 + errorTolerance)
      );

      expect(backingBalanceU2).to.be.least(
        bnFloatMultiplier(principalBalanceU2, 1 - errorTolerance)
      );
      expect(backingBalanceU2).to.be.most(
        bnFloatMultiplier(principalBalanceU2, 1 + errorTolerance)
      );
    });

    it("Should only allow setting speedbump once and after expiration", async () => {
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

      // Deposit so it's possible to make a loss
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      // set pool interest accumulated to -50%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.5)
      );
      // No pre redemption speedbump
      await expect(fixture.tranche.hitSpeedbump()).to.be.revertedWith(
        "E:Not Expired"
      );
      // Allow setting it
      advanceTime(provider, expiration);
      await fixture.tranche.hitSpeedbump();
      // It cannot be set again
      await expect(fixture.tranche.hitSpeedbump()).to.be.revertedWith(
        "E:AlreadySet"
      );
      advanceTime(provider, forty_eight_hours);
      // It cannot be set again even after it's not active
      await expect(fixture.tranche.hitSpeedbump()).to.be.revertedWith(
        "E:AlreadySet"
      );
    });

    it("Should only allow setting the speedbump when there is a real loss", async () => {
      // Deposit so it's possible to make a loss
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      // Allow setting it
      advanceTime(provider, expiration);
      // Try setting without a loss
      await expect(fixture.tranche.hitSpeedbump()).to.be.revertedWith(
        "E:NoLoss"
      );
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
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

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
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to 50%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.5)
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

      const interestAdjusted = bnFloatMultiplier(initialBalance, 1.5);
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
      ).to.be.revertedWith("E:Not Expired");
      await expect(
        fixture.tranche.connect(user1).withdrawPrincipal(1, user1Address)
      ).to.be.revertedWith("E:Not Expired");
    });
    it("should prevent withdraw of principal tokens when the interest rate is negative and speedbump hasn't been hit", async () => {
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to -50%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.5)
      );

      advanceTime(provider, expiration);

      await expect(
        fixture.tranche
          .connect(user1)
          .withdrawPrincipal(initialBalance, user1Address)
      ).to.be.revertedWith("E:NEG_INT");
    });

    it("should prevent withdraw of principal tokens when the interest rate is negative and speedbump was hit less than 48 hours ago", async () => {
      const initialUnderlying =
        await fixture.positionStub.underlyingUnitValue();

      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user1Address);

      // set pool interest accumulated to -50%
      await fixture.positionStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.5)
      );

      advanceTime(provider, expiration);

      await fixture.tranche.hitSpeedbump();

      advanceTime(provider, forty_eight_hours / 2);

      await expect(
        fixture.tranche
          .connect(user1)
          .withdrawPrincipal(initialBalance, user1Address)
      ).to.be.revertedWith("E:Early");
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

    it("Should assign names and symbols correctly", async () => {
      expect(await fixture.tranche.symbol()).to.be.eq(
        "ePTestWrappedPosition-20NOV86"
      );
      expect(await fixture.tranche.name()).to.be.eq(
        "Element Principal Token TestWrappedPosition-20NOV86"
      );
    });
  });
});
