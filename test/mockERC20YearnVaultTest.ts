import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { MockERC20YearnVault__factory } from "typechain/factories/MockERC20YearnVault__factory";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { MockERC20YearnVault } from "typechain/MockERC20YearnVault";
import { TestERC20 } from "typechain/TestERC20";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime } from "./helpers/time";

const { provider } = waffle;

describe("MockERC20YearnVault", function () {
  let users: { user: Signer; address: string }[];
  let token: TestERC20;
  let vault: MockERC20YearnVault;
  let userBalance: BigNumber;
  let depositValue: BigNumber;
  before(async function () {
    await createSnapshot(provider);
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

    const TokenDeployer = new TestERC20__factory(users[0].user);
    const VaultDeployer = new MockERC20YearnVault__factory(users[0].user);

    token = await TokenDeployer.deploy("token", "TKN", 18);
    vault = await VaultDeployer.deploy(token.address);

    userBalance = BigNumber.from(1000000000000);
    depositValue = BigNumber.from(100000);

    await token.connect(users[1].user).mint(users[1].address, userBalance);
    await token.connect(users[1].user).approve(vault.address, userBalance);
    await token.connect(users[2].user).mint(users[2].address, userBalance);
    await token.connect(users[2].user).approve(vault.address, userBalance);
    // user0 tokens for interest rate manipulation
    await token.connect(users[0].user).mint(users[0].address, userBalance);
    await token.connect(users[0].user).approve(vault.address, userBalance);
  });
  after(async () => {
    await restoreSnapshot(provider);
  });
  beforeEach(async () => {
    await createSnapshot(provider);
  });
  afterEach(async () => {
    await restoreSnapshot(provider);
  });
  describe("deposit - withdraw", () => {
    it("correctly handles deposits and withdrawals", async () => {
      // first deposit, shares received = tokens deposited
      await vault
        .connect(users[1].user)
        .deposit(depositValue.div(2), users[1].address);
      expect(await vault.balanceOf(users[1].address)).to.equal(
        depositValue.div(2)
      );

      // second deposit, no interest, shares Received = tokens deposited
      await vault
        .connect(users[1].user)
        .deposit(depositValue.div(2), users[1].address);
      expect(await vault.balanceOf(users[1].address)).to.equal(depositValue);

      // user[0] doubles the total tokens held in the vault, this simulates a 100% interest.
      // this is not done through the report() function and therefore is instant and not
      // subject to the unlock period.
      await token.connect(users[0].user).transfer(vault.address, depositValue);

      // third deposit with 100% interest. Vault shares received should be half the value deposited
      await vault
        .connect(users[2].user)
        .deposit(depositValue, users[2].address);
      await vault
        .connect(users[1].user)
        .deposit(depositValue.mul(2), users[1].address);

      expect(await vault.balanceOf(users[2].address)).to.equal(
        depositValue.div(2)
      );
      expect(await vault.balanceOf(users[1].address)).to.equal(
        depositValue.mul(2)
      );

      // fist withdrawal, user[1] half withdrawal.
      await vault
        .connect(users[1].user)
        .withdraw(depositValue, users[1].address, 0);
      // second withdrawal, user[1] half withdrawal.
      await vault
        .connect(users[1].user)
        .withdraw(depositValue, users[1].address, 0);
      // expected interest = depositValue
      expect(await token.balanceOf(users[1].address)).to.equal(
        userBalance.add(depositValue)
      );

      // third withdrawal, user[2] full value
      await vault
        .connect(users[2].user)
        .withdraw(depositValue.div(2), users[2].address, 0);
      // user[2] deposited after interest accrual, and should therefore receive only the
      // initial deposit back
      expect(await token.balanceOf(users[2].address)).to.equal(userBalance);

      // check that the vault is empty after everything was withdrawn
      expect(await token.balanceOf(vault.address)).to.equal(0);
      expect(await vault.totalSupply()).to.equal(0);
    });
  });
  describe("deposit - withdraw with rewards unlock", () => {
    it("correctly handles deposits and withdrawals", async () => {
      // rewards unlocked in 1 block. Does not multiply.
      const blockError = depositValue.div(
        BigNumber.from(1000000).div(BigNumber.from(46))
      );
      // first deposit, shares received = tokens deposited
      // totalShares = depositValue
      // totalAssets = depositValue
      await vault
        .connect(users[1].user)
        .deposit(depositValue, users[1].address);
      expect(await vault.balanceOf(users[1].address)).to.equal(depositValue);

      // report 100% gain
      await vault.connect(users[0].user).report(depositValue);

      // fist withdrawal, half time has passed so half the interest should be reflected
      await createSnapshot(provider);
      advanceTime(provider, 10868);
      await vault
        .connect(users[1].user)
        .withdraw(depositValue, users[1].address, 0);
      let balance = await token.balanceOf(users[1].address);
      expect(balance.toNumber()).to.be.closeTo(
        userBalance.add(depositValue.div(2)).add(blockError.div(2)).toNumber(),
        12
      );
      await restoreSnapshot(provider);

      // fist withdrawal, full time has passed so the full interest should  be reflected
      await createSnapshot(provider);
      advanceTime(provider, 22000);
      await vault
        .connect(users[1].user)
        .withdraw(depositValue, users[1].address, 0);
      balance = await token.balanceOf(users[1].address);
      expect(balance.toNumber()).to.be.closeTo(
        userBalance.add(depositValue).toNumber(),
        12
      );
      await restoreSnapshot(provider);

      // fist withdrawal, no time has passed so the interest should not be reflected
      await createSnapshot(provider);
      await vault
        .connect(users[1].user)
        .withdraw(depositValue, users[1].address, 0);
      balance = await token.balanceOf(users[1].address);
      expect(balance.toNumber()).to.be.closeTo(userBalance.toNumber(), 12);

      // No vault shares should remain, but there should still be tokens locked in the vault
      expect(await vault.totalSupply()).to.equal(0);

      // future deposits should not benefit from the locked token balance.
      // However there is an edge case where if rewards are unlocking and
      // the vault is empty, any small deposit will be enough to drain the remainder
      // of the unlocked value. The below logic demonstrates this.
      await vault.connect(users[2].user).deposit(1, users[2].address);
      advanceTime(provider, 22000);
      await vault.connect(users[2].user).withdraw(1, users[2].address, 0);
      expect(await token.balanceOf(users[2].address)).to.equal(
        userBalance.add(depositValue).sub(blockError)
      );
      await restoreSnapshot(provider);

      // fist withdrawal, no time has passed so the interest should not be reflected.
      // all but 1 tokens withdrawn so the above edge case is not triggered.
      await createSnapshot(provider);
      await vault
        .connect(users[1].user)
        .withdraw(depositValue.sub(1), users[1].address, 0);
      balance = await token.balanceOf(users[1].address);
      expect(balance.toNumber()).to.be.closeTo(userBalance.toNumber(), 12);

      // there should only 1 vault share
      expect(await vault.totalSupply()).to.equal(1);

      // future deposits should not benefit from the locked token balance since the
      // vault is not empty. The user should only be able to withdraw what they put in
      await vault
        .connect(users[2].user)
        .deposit(depositValue.mul(100), users[2].address);

      advanceTime(provider, 22000);
      await vault.connect(users[2].user).withdraw(100, users[2].address, 0);
      balance = await token.balanceOf(users[2].address);
      expect(balance.toNumber()).to.be.closeTo(userBalance.toNumber(), 12);

      // The single remaining vault share can be used to withdraw all unlocked tokens
      await vault.connect(users[1].user).withdraw(1, users[1].address, 0);
      balance = await token.balanceOf(users[1].address);
      expect(balance.toNumber()).to.be.closeTo(
        userBalance.add(depositValue).toNumber(),
        12
      );

      await restoreSnapshot(provider);
    });
  });
});
