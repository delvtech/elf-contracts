import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import { FixtureInterface, loadFixture } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

import { TestYVault } from "../typechain/TestYVault";
import { TestYVault__factory } from "../typechain/factories/TestYVault__factory";

const { provider } = waffle;

describe("Wrapped Position", () => {
  let users: { user: Signer; address: string }[];
  let fixture: FixtureInterface;
  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts
    fixture = await loadFixture();

    // begin to populate the user array by assigning each index a signer
    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return { user, address: "" };
    });

    // finish populating the user array by assigning each index a signer address
    // and approve 6e6 usdc to the position contract for each address
    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
        await fixture.usdc.mint(userInfo.address, 7e6);
        await fixture.usdc
          .connect(user)
          .approve(fixture.position.address, 12e6);
      })
    );

    // Make an initial deposit in the aypool contract
    // This prevents a div by zero reversion in several cases
    await fixture.usdc.mint(users[0].address, 100);
    await fixture.usdc.approve(fixture.yusdc.address, 100);
    await fixture.yusdc.deposit(100, users[0].address);
  });
  after(async () => {
    // revert back to initial state after all tests pass
    await restoreSnapshot(provider);
  });
  describe("balanceOfUnderlying", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should return the correct balance", async () => {
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e6);

      expect(
        await fixture.position.balanceOfUnderlying(users[1].address)
      ).to.equal(1e6);
    });
  });
  // WARNING: Tests from now on do not use snapshots. They are interdependent!
  describe("deposit", () => {
    it("should correctly track deposits", async () => {
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e6);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(1e6);

      await fixture.position
        .connect(users[2].user)
        .deposit(users[2].address, 2e6);
      expect(await fixture.position.balanceOf(users[2].address)).to.equal(2e6);

      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e6);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(2e6);

      await fixture.position
        .connect(users[3].user)
        .deposit(users[3].address, 6e6);
      expect(await fixture.position.balanceOf(users[3].address)).to.equal(6e6);
    });
  });
  describe("transfer", () => {
    it("should correctly transfer value", async () => {
      await fixture.position
        .connect(users[3].user)
        .deposit(users[3].address, 6e6);

      // Update vault to 1 share = 1.1 USDC
      await fixture.yusdc.updateShares();
      await fixture.position
        .connect(users[3].user)
        .transfer(users[1].address, 5e6);
      expect(await fixture.position.balanceOf(users[3].address)).to.equal(1e6);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(5e6);
    });
  });
  describe("withdraw", () => {
    it("should correctly withdraw value", async () => {
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 7e6);
      await fixture.position
        .connect(users[2].user)
        .deposit(users[2].address, 2e6);
      await fixture.position
        .connect(users[3].user)
        .deposit(users[3].address, 1e6);
      /* At this point:
       * User 1: 7 shares
       * user 2: 2 shares
       * User 3: 1 shares
       * These shares are worth 11 USDC
       */
      await fixture.position
        .connect(users[1].user)
        .withdraw(users[1].address, 1e6, 0);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(6e6);

      const shareBalanceUser0 = await fixture.position.balanceOf(
        users[1].address
      );
      const shareBalanceUser1 = await fixture.position.balanceOf(
        users[2].address
      );
      const shareBalanceUser2 = await fixture.position.balanceOf(
        users[3].address
      );

      await fixture.position
        .connect(users[1].user)
        .withdraw(users[1].address, shareBalanceUser0, 0);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(0);

      await fixture.position
        .connect(users[2].user)
        .withdraw(users[2].address, shareBalanceUser1, 0);
      expect(await fixture.position.balanceOf(users[2].address)).to.equal(0);

      await fixture.position
        .connect(users[3].user)
        .withdraw(users[3].address, shareBalanceUser2, 0);
      expect(await fixture.position.balanceOf(users[3].address)).to.equal(0);

      const usdcBalanceUser0 = await fixture.usdc.balanceOf(users[1].address);
      const usdcBalanceUser1 = await fixture.usdc.balanceOf(users[2].address);
      const usdcBalanceUser2 = await fixture.usdc.balanceOf(users[3].address);

      const totalUsdcBalance = usdcBalanceUser0
        .add(usdcBalanceUser1)
        .add(usdcBalanceUser2);
      expect(totalUsdcBalance).to.equal(ethers.BigNumber.from("21000000"));
    });
  });
  describe("Yearn migration", async () => {
    let newVault: TestYVault;

    before(async () => {
      // Deploy a new version
      const yearnDeployer = new TestYVault__factory(users[0].user);
      newVault = await yearnDeployer.deploy(
        fixture.usdc.address,
        await fixture.usdc.decimals()
      );
      // Deposit into it and set the ratio
      await fixture.usdc.mint(users[0].address, 100);
      await fixture.usdc.approve(newVault.address, 100);
      await newVault.deposit(100, users[0].address);
      // This ensures theirs a difference between the price per shares
      await newVault.updateShares();
      await newVault.updateShares();
    });
    // tests are independent
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });

    it("Allows governance to upgrade", async () => {
      await fixture.position.transition(newVault.address, 0);
      const conversionRate = await fixture.position.conversionRate();
      // Magic hex is 1.1 in 18 point fixed
      expect(conversionRate).to.be.eq(BigNumber.from("0x10cac896d2390000"));
    });

    it("Blocks non governance upgrades", async () => {
      const tx = fixture.position
        .connect(users[2].user)
        .transition(newVault.address, 0);
      await expect(tx).to.be.revertedWith("Sender not owner");
    });

    it("Blocks withdraw which does not product enough tokens", async () => {
      const tx = fixture.position.transition(
        newVault.address,
        ethers.constants.MaxUint256
      );
      await expect(tx).to.be.revertedWith("Not enough output");
    });

    it("Makes consistent deposits", async () => {
      // We check that a deposit before an upgrade gets the same amount of shares as one after
      await fixture.position.deposit(users[0].address, 1e6);
      const beforeBalance = await fixture.position.balanceOf(users[0].address);
      await fixture.position.transition(newVault.address, 0);
      await fixture.position.deposit(users[1].address, 1e6);
      const afterBalance = await fixture.position.balanceOf(users[1].address);
      // There are very small rounding errors leading to -1
      expect(beforeBalance.sub(1)).to.be.eq(afterBalance);
    });

    // We check that after a transition you can still withdraw the same amount
    it("Makes consistent withdraws", async () => {
      // NOTE - Because of a rounding error bug the conversion rate mechanic can cause withdraw
      //        failure for the last withdraw. we fix here by having a second deposit
      await fixture.position.deposit(users[1].address, 5e5);
      // Deposit and transition
      await fixture.position.deposit(users[0].address, 1e6);
      const beforeBalanceToken = await fixture.usdc.balanceOf(users[0].address);
      const beforeBalanceShares = await fixture.position.balanceOf(
        users[0].address
      );
      await fixture.position.transition(newVault.address, 0);
      // Withdraw and check balances
      await fixture.position.withdraw(users[0].address, beforeBalanceShares, 0);
      const afterBalanceToken = await fixture.usdc.balanceOf(users[0].address);
      // Minus one to allow for rounding error
      expect(afterBalanceToken.sub(beforeBalanceToken)).to.be.eq(1e6 - 1);
    });

    it("has consistent price per share over upgrades", async () => {
      const priceBefore = await fixture.position.getSharesToUnderlying(1e6);
      await fixture.position.transition(newVault.address, 0);
      const priceAfter = await fixture.position.getSharesToUnderlying(1e6);
      // Allow some rounding
      expect(priceAfter.sub(priceBefore).lt(10)).to.be.true;
    });
  });

  describe("Pause tests", async () => {
    before(async () => {
      // Pause the contract
      await fixture.position.pause(true);
    });

    it("Can't deposit", async () => {
      const tx = fixture.position.deposit(users[0].address, 100);
      await expect(tx).to.be.revertedWith("Paused");
    });

    it("Can't withdraw", async () => {
      const tx = fixture.position.withdraw(users[0].address, 0, 0);
      await expect(tx).to.be.revertedWith("Paused");
    });

    it("Only useable by authorized", async () => {
      const tx = fixture.position.connect(users[1].user).pause(false);
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
  });
});
