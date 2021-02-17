import {ethers} from "hardhat";

import {bnFloatMultiplier} from "./helpers/math";
import {loadFixture, fixtureInterface} from "./helpers/deployer";
import {createSnapshot, restoreSnapshot} from "./helpers/snapshots";
import {advanceTime} from "./helpers/time";

import {expect} from "chai";
import {Signer} from "ethers";

const {waffle} = require("hardhat");
const provider = waffle.provider;

describe("Tranche", () => {
  let fixture: fixtureInterface;
  let user1: Signer;
  let user2: Signer;
  let user1Address: string;
  let user2Address: string;
  let lockDuration = 5000000; //seconds
  let initialBalance = ethers.BigNumber.from("2000000000"); // 2e9

  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts
    fixture = await loadFixture();

    [user1, user2] = await ethers.getSigners();
    user1Address = await user1.getAddress();
    user2Address = await user2.getAddress();

    await fixture.elfStub.connect(user1).mint(user1Address, initialBalance);
    await fixture.elfStub.connect(user1).approve(fixture.tranche.address, 2e9);

    await fixture.elfStub.connect(user2).mint(user2Address, initialBalance);
    await fixture.elfStub.connect(user2).approve(fixture.tranche.address, 2e9);
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
      await expect(
        fixture.tranche.connect(user1).deposit(initialBalance)
      ).to.be.revertedWith("expired");
    });
    it("should correctly handle deposits with no accrued interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);
      await fixture.tranche.connect(user2).deposit(initialBalance);

      // check for correct YC balance
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(initialBalance);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(initialBalance);

      // check for correct FYT balance
      expect(await fixture.tranche.balanceOf(user1Address)).to.equal(
        initialBalance.mul(initialUnderlying)
      );
      expect(await fixture.tranche.balanceOf(user2Address)).to.equal(
        initialBalance.mul(initialUnderlying)
      );

      // check that the backing tokens were transferred
      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(0);
    });
    it("should correctly handle deposits with accrued interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);

      // set pool interest accululated to 20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche.connect(user2).deposit(initialBalance);

      // check for correct YC balance
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(initialBalance);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(initialBalance);

      // check for correct FYT balance.
      // given the same ELF token input, the user should always gain the same FYT output.
      expect(await fixture.tranche.balanceOf(user1Address)).to.equal(
        initialBalance.mul(initialUnderlying)
      );
      expect(await fixture.tranche.balanceOf(user2Address)).to.equal(
        initialBalance.mul(initialUnderlying)
      );
    });
    it("should correctly handle deposits with negative interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);

      // set pool interest accululated to -20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.1)
      );

      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      expect(bnFloatMultiplier(fytBalanceU1, 0.1)).to.equal(fytBalanceU2);

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
      await fixture.tranche.connect(user1).deposit(initialBalance);
      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawFyt(fytBalanceU1);
      await fixture.tranche.connect(user2).withdrawFyt(fytBalanceU2);

      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(
        initialBalance
      );
    });
    it("should correctly handle FYT withdrawals with accrued interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);

      // set pool interest accululated to 20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawFyt(fytBalanceU1);
      await fixture.tranche.connect(user2).withdrawFyt(fytBalanceU2);

      // given the same backing token input, the users should gain the same FYT output
      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(
        await fixture.elfStub.balanceOf(user2Address)
      );
    });
    it("should correctly handle YC withdrawals with no accrued interest", async () => {
      await fixture.tranche.connect(user1).deposit(initialBalance);
      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawYc(ycBalanceU1);
      await fixture.tranche.connect(user2).withdrawYc(ycBalanceU2);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);
    });
    it("should correctly handle YC withdrawals with accrued interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);

      // set pool interest accululated to 20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 1.2)
      );

      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawYc(ycBalanceU1);
      await fixture.tranche.connect(user2).withdrawYc(ycBalanceU2);

      // given the same backing token input, the users should gain the same YC output
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(
        await fixture.yc.balanceOf(user2Address)
      );
    });
    it("should correctly handle YC withdrawals with negative interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);

      // set pool interest accululated to -20%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.2)
      );

      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawYc(ycBalanceU1);
      await fixture.tranche.connect(user2).withdrawYc(ycBalanceU2);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);

      // YCs should not be worth any backing tokens if interest is negative
      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(0);
    });
    it("should correctly handle FYT withdrawals with negative interest", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);

      // set pool interest accululated to -50%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.5)
      );

      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      expect(bnFloatMultiplier(fytBalanceU1, 0.5)).to.equal(fytBalanceU2);

      await fixture.tranche.connect(user1).withdrawFyt(fytBalanceU1);
      await fixture.tranche.connect(user2).withdrawFyt(fytBalanceU2);

      const backingBalanceU1 = await fixture.elfStub.balanceOf(user1Address);
      const backingBalanceU2 = await fixture.elfStub.balanceOf(user2Address);

      expect(bnFloatMultiplier(backingBalanceU1, 0.5).add(1)).to.equal(
        backingBalanceU2
      );
    });
    it("should correctly handle full withdrawals with no accrued interest - withdraw YC, then FYT", async () => {
      await fixture.tranche.connect(user1).deposit(initialBalance);
      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawYc(ycBalanceU1);
      await fixture.tranche.connect(user2).withdrawYc(ycBalanceU2);
      await fixture.tranche.connect(user1).withdrawFyt(fytBalanceU1);
      await fixture.tranche.connect(user2).withdrawFyt(fytBalanceU2);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);
      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.yc.totalSupply()).to.equal(0);
      expect(await fixture.tranche.totalSupply()).to.equal(0);
      expect(await fixture.elfStub.balanceOf(fixture.tranche.address)).to.equal(
        0
      );
    });
    it("should correctly handle full withdrawals with no accrued interest - withdraw FYT, then YC", async () => {
      await fixture.tranche.connect(user1).deposit(initialBalance);
      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawFyt(fytBalanceU1);
      await fixture.tranche.connect(user2).withdrawFyt(fytBalanceU2);
      await fixture.tranche.connect(user1).withdrawYc(ycBalanceU1);
      await fixture.tranche.connect(user2).withdrawYc(ycBalanceU2);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);
      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.yc.totalSupply()).to.equal(0);
      expect(await fixture.tranche.totalSupply()).to.equal(0);
      expect(await fixture.elfStub.balanceOf(fixture.tranche.address)).to.equal(
        0
      );
    });
    it("should correctly handle full withdrawals with accrued interest -  withdraw YC, then FYT", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);

      // set pool interest accululated to 100%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 2)
      );

      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawYc(ycBalanceU1);
      await fixture.tranche.connect(user2).withdrawYc(ycBalanceU2);
      await fixture.tranche.connect(user1).withdrawFyt(fytBalanceU1);
      await fixture.tranche.connect(user2).withdrawFyt(fytBalanceU2);

      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(
        await fixture.elfStub.balanceOf(user2Address)
      );
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(
        await fixture.yc.balanceOf(user2Address)
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.yc.totalSupply()).to.equal(0);
      expect(await fixture.tranche.totalSupply()).to.equal(0);
      expect(await fixture.elfStub.balanceOf(fixture.tranche.address)).to.equal(
        0
      );
    });
    it("should correctly handle full withdrawals with accrued interest -  withdraw FYT, then YC", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);

      // set pool interest accululated to 100%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 2)
      );

      await fixture.tranche.connect(user2).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawFyt(fytBalanceU1);
      await fixture.tranche.connect(user2).withdrawFyt(fytBalanceU2);
      await fixture.tranche.connect(user1).withdrawYc(ycBalanceU1);
      await fixture.tranche.connect(user2).withdrawYc(ycBalanceU2);

      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(
        await fixture.elfStub.balanceOf(user2Address)
      );
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(
        await fixture.yc.balanceOf(user2Address)
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.yc.totalSupply()).to.equal(0);
      expect(await fixture.tranche.totalSupply()).to.equal(0);
      expect(await fixture.elfStub.balanceOf(fixture.tranche.address)).to.equal(
        0
      );
    });
    it("should correctly handle full withdrawals with negative interest - withdraw YC, then FYT", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);
      await fixture.tranche.connect(user2).deposit(initialBalance);

      // set interest to -10%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.9)
      );

      advanceTime(provider, lockDuration);

      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(0);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawYc(ycBalanceU1);
      await fixture.tranche.connect(user2).withdrawYc(ycBalanceU2);
      await fixture.tranche.connect(user1).withdrawFyt(fytBalanceU1);
      await fixture.tranche.connect(user2).withdrawFyt(fytBalanceU2);

      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);

      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.yc.totalSupply()).to.equal(0);
      expect(await fixture.tranche.totalSupply()).to.equal(0);
      expect(await fixture.elfStub.balanceOf(fixture.tranche.address)).to.equal(
        0
      );
    });
    it("should correctly handle full withdrawals with negative interest - withdraw FYT, then YC", async () => {
      const initialUnderlying = await fixture.elfStub.underlyingUnitValue();

      await fixture.tranche.connect(user1).deposit(initialBalance);
      await fixture.tranche.connect(user2).deposit(initialBalance);

      // set interest to -10%
      await fixture.elfStub.setSharesToUnderlying(
        bnFloatMultiplier(initialUnderlying, 0.9)
      );

      advanceTime(provider, lockDuration);

      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(0);

      const ycBalanceU1 = await fixture.yc.balanceOf(user1Address);
      const ycBalanceU2 = await fixture.yc.balanceOf(user2Address);
      const fytBalanceU1 = await fixture.tranche.balanceOf(user1Address);
      const fytBalanceU2 = await fixture.tranche.balanceOf(user2Address);

      await fixture.tranche.connect(user1).withdrawFyt(fytBalanceU1);
      await fixture.tranche.connect(user2).withdrawFyt(fytBalanceU2);
      await fixture.tranche.connect(user1).withdrawYc(ycBalanceU1);
      await fixture.tranche.connect(user2).withdrawYc(ycBalanceU2);

      expect(await fixture.elfStub.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.elfStub.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // ensure that all FYTs and YCs were burned and the tranche balance is 0
      expect(await fixture.yc.balanceOf(user1Address)).to.equal(0);
      expect(await fixture.yc.balanceOf(user2Address)).to.equal(0);
      expect(await fixture.yc.totalSupply()).to.equal(0);
      expect(await fixture.tranche.totalSupply()).to.equal(0);
      expect(await fixture.elfStub.balanceOf(fixture.tranche.address)).to.equal(
        0
      );
    });
    it("should prevent withdrawal of FYTs and YCs before the tranche expires ", async () => {
      await fixture.tranche.connect(user1).deposit(initialBalance);
      await fixture.tranche.connect(user2).deposit(initialBalance);

      await expect(
        fixture.tranche.connect(user1).withdrawYc(1)
      ).to.be.revertedWith("not expired yet");
      await expect(
        fixture.tranche.connect(user1).withdrawFyt(1)
      ).to.be.revertedWith("not expired yet");
    });
    it("should prevent withdrawal of more FYTs and YCs than the user has", async () => {
      await fixture.tranche.connect(user1).deposit(initialBalance);

      advanceTime(provider, lockDuration);

      const user1FytBalance = await fixture.tranche.balanceOf(user1Address);
      await expect(
        fixture.tranche.connect(user1).withdrawYc(initialBalance.add(1))
      ).to.be.reverted;
      await expect(
        fixture.tranche.connect(user1).withdrawFyt(user1FytBalance.add(1))
      ).to.be.reverted;
    });
  });
});
