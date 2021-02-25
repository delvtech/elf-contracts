import {ethers} from "hardhat";
import {loadFixture, fixtureInterface} from "./helpers/deployer";
import {createSnapshot, restoreSnapshot} from "./helpers/snapshots";

import {expect} from "chai";
import {Signer} from "ethers";

const {waffle} = require("hardhat");
const provider = waffle.provider;

describe("Elf", () => {
  let users: {user: Signer; address: string}[];
  let fixture: fixtureInterface;
  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts
    fixture = await loadFixture();

    // begin to populate the user array by assigning each index a signer
    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return {user, address: ""};
    });

    // finish populating the user array by assigning each index a signer address
    // and approve 6e6 usdc to the elf contract for each address
    await Promise.all(
      users.map(async (userInfo) => {
        let user = userInfo.user;
        userInfo.address = await user.getAddress();
        await fixture.usdc.mint(userInfo.address, 6e6);
        await fixture.usdc.connect(user).approve(fixture.elf.address, 6e6);
      })
    );
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
      await fixture.elf.connect(users[1].user).deposit(users[1].address, 1e6);

      expect(await fixture.elf.balanceOfUnderlying(users[1].address)).to.equal(
        1e6
      );
    });
  });
  // WARNING: Tests from now on do not use snapshots. They are interdependant!
  describe("deposit", () => {
    it("should correctly track deposits", async () => {
      await fixture.elf.connect(users[1].user).deposit(users[1].address, 1e6);
      expect(await fixture.elf.balanceOf(users[1].address)).to.equal(1e6);

      await fixture.elf.connect(users[2].user).deposit(users[2].address, 2e6);
      expect(await fixture.elf.balanceOf(users[2].address)).to.equal(2e6);

      await fixture.elf.connect(users[1].user).deposit(users[1].address, 1e6);
      expect(await fixture.elf.balanceOf(users[1].address)).to.equal(2e6);

      await fixture.elf.connect(users[3].user).deposit(users[3].address, 6e6);
      expect(await fixture.elf.balanceOf(users[3].address)).to.equal(6e6);
    });
  });
  describe("transfer", () => {
    it("should correctly transfer value", async () => {
      /* At this point:
       * User 1: 2 USDC deposited
       * user 2: 2 USDC deposited
       * User 3: 6 USDC deposited
       */
      // Update vault to 1 share = 1.1 USDC
      await fixture.yusdc.updateShares();
      await fixture.elf.connect(users[3].user).transfer(users[1].address, 5e6);
      expect(await fixture.elf.balanceOf(users[3].address)).to.equal(1e6);
      expect(await fixture.elf.balanceOf(users[1].address)).to.equal(7e6);
    });
  });
  describe("withdraw", () => {
    it("should correctly withdraw value", async () => {
      /* At this point:
       * User 1: 7 shares
       * user 2: 2 shares
       * User 3: 1 shares
       * These shares are worth 11 USDC
       */
      await fixture.elf
        .connect(users[1].user)
        .withdraw(users[1].address, 1e6, 0);
      expect(await fixture.elf.balanceOf(users[1].address)).to.equal(6e6);

      const elfBalanceUser0 = await fixture.elf.balanceOf(users[1].address);
      const elfBalanceUser1 = await fixture.elf.balanceOf(users[2].address);
      const elfBalanceUser2 = await fixture.elf.balanceOf(users[3].address);

      await fixture.elf
        .connect(users[1].user)
        .withdraw(users[1].address, elfBalanceUser0, 0);
      expect(await fixture.elf.balanceOf(users[1].address)).to.equal(0);

      await fixture.elf
        .connect(users[2].user)
        .withdraw(users[2].address, elfBalanceUser1, 0);
      expect(await fixture.elf.balanceOf(users[2].address)).to.equal(0);

      await fixture.elf
        .connect(users[3].user)
        .withdraw(users[3].address, elfBalanceUser2, 0);
      expect(await fixture.elf.balanceOf(users[3].address)).to.equal(0);

      const usdcBalaceUser0 = await fixture.usdc.balanceOf(users[1].address);
      const usdcBalaceUser1 = await fixture.usdc.balanceOf(users[2].address);
      const usdcBalaceUser2 = await fixture.usdc.balanceOf(users[3].address);

      const totalUsdcBalance = usdcBalaceUser0
        .add(usdcBalaceUser1)
        .add(usdcBalaceUser2);
      expect(totalUsdcBalance).to.equal(ethers.BigNumber.from("19000000"));
    });
  });
});
