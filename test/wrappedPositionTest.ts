import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import { FixtureInterface, loadFixture } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

import { TestYVaultV4 } from "typechain/TestYVaultV4";
import { YVaultV4AssetProxy } from "typechain/YVaultV4AssetProxy";

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
        await fixture.usdc.mint(userInfo.address, 6e6);
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
  describe("Version locked deployments", () => {
    it("Wont deploy YAssetProxy with a v4 yearn vault", async () => {
      // Deploy a mock yearn v4
      const mockYearnV4Factory = await ethers.getContractFactory(
        "TestYVaultV4"
      );
      const yVaultV4 = await mockYearnV4Factory.deploy(
        fixture.usdc.address,
        await fixture.usdc.decimals()
      );
      // Attempt to deploy a non v4 wp on it
      const yearnWPFactory = await ethers.getContractFactory(
        "YVaultAssetProxy"
      );
      const tx = yearnWPFactory.deploy(
        yVaultV4.address,
        fixture.usdc.address,
        "mock yearn",
        "my"
      );
      await expect(tx).to.be.revertedWith("Unsupported Version");
    });
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
      /* At this point:
       * User 1: 2 USDC deposited
       * user 2: 2 USDC deposited
       * User 3: 6 USDC deposited
       */
      // Update vault to 1 share = 1.1 USDC
      await fixture.yusdc.updateShares();
      await fixture.position
        .connect(users[3].user)
        .transfer(users[1].address, 5e6);
      expect(await fixture.position.balanceOf(users[3].address)).to.equal(1e6);
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(7e6);
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
      expect(totalUsdcBalance).to.equal(ethers.BigNumber.from("19000000"));
    });
  });
  // These tests are of the reserve mechanic
  describe("Reserve deposit and withdraw", async () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("Successfully deposits", async () => {
      // Create some underlying
      await fixture.usdc.mint(users[0].address, 100e6);
      // Approve the wrapped position reserve
      await fixture.usdc.approve(fixture.position.address, 100e6);
      // deposit to the reserves
      await fixture.position.reserveDeposit(10e6);
      expect(await fixture.position.reserveUnderlying()).to.be.eq(10e6 - 1);
      expect(await fixture.position.reserveShares()).to.be.eq(0);
      expect(await fixture.position.reserveBalances(users[0].address)).to.be.eq(
        10e6
      );
      expect(await fixture.position.reserveSupply()).to.be.eq(10e6);
      // We make a small deposit to change the reserve
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e6);
      // NOTE - THIS CONSTANT DEPENDS ON THE PREVIOUS TEST SETTING THE DEPOSIT RATE
      expect(await fixture.position.balanceOf(users[1].address)).to.equal(
        909090
      );
      // We then make a new reserve deposit
      await fixture.position.connect(users[2].user).reserveDeposit(1e6);
      expect(await fixture.position.reserveUnderlying()).to.be.eq(1e6);
      expect(await fixture.position.reserveShares()).to.be.eq(9090909);
      expect(await fixture.position.reserveBalances(users[2].address)).to.be.eq(
        1e6
      );
      expect(await fixture.position.reserveSupply()).to.be.eq(11e6);
    });

    it("Successfully withdraws", async () => {
      // Create some underlying
      await fixture.usdc.mint(users[0].address, 10e6);
      // Approve the position reserve
      await fixture.usdc.approve(fixture.position.address, 100e6);
      // deposit to the reserve
      await fixture.position.reserveDeposit(10e6);
      const balanceStart = await fixture.usdc.balanceOf(users[0].address);
      // We do a trial withdraw
      await fixture.position.reserveWithdraw(1e6);
      let currentBalance = await fixture.usdc.balanceOf(users[0].address);
      // Note - this is slightly less because underlying reserves are missing
      //        exactly one unit of usdc
      expect(currentBalance).to.be.eq(balanceStart.add(999999));
      // We now check that reserve withdraws with shares present work properly
      // Make a trade which requires local shares
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, 1e6);
      expect(await fixture.position.reserveShares()).to.be.eq(8181819);
      // We now make a withdraw and check that the right amount is produced
      await fixture.position.reserveWithdraw(1e6);
      currentBalance = await fixture.usdc.balanceOf(users[0].address);
      expect(currentBalance).to.be.eq(balanceStart.add(999999).add(1e6));
      expect(await fixture.position.reserveShares()).to.be.eq(7272728);
    });
  });
  // We test explicity only the functionality changes in V4 not the whole
  // contract
  describe("Wrapped Yearn Vault v4 upgrade", async () => {
    let vaultV4: TestYVaultV4;
    let wpV4: YVaultV4AssetProxy;

    before(async () => {
      // Deploy a mock yearn v4
      const mockYearnV4Factory = await ethers.getContractFactory(
        "TestYVaultV4"
      );
      // TODO - Update so that the ethers factories play nice with types
      vaultV4 = (await mockYearnV4Factory.deploy(
        fixture.usdc.address,
        await fixture.usdc.decimals()
      )) as TestYVaultV4;
      // Deploy a wrapped position
      const wpFactory = await ethers.getContractFactory("YVaultV4AssetProxy");
      wpV4 = (await wpFactory.deploy(
        vaultV4.address,
        fixture.usdc.address,
        "mock yearn v4",
        "test"
      )) as YVaultV4AssetProxy;
      // set approvals for accounts
      await fixture.usdc.approve(wpV4.address, ethers.constants.MaxUint256);
      await fixture.usdc
        .connect(users[1].user)
        .approve(wpV4.address, ethers.constants.MaxUint256);
      // deposit into the yearn vault so there's a supply
      await fixture.usdc.approve(vaultV4.address, ethers.constants.MaxUint256);
      await vaultV4.deposit(1e6, users[0].address);
    });

    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      // revert back to initial state after all tests pass
      await restoreSnapshot(provider);
    });

    it("Won't deploy on a v3 wrapped position", async () => {
      const wpFactory = await ethers.getContractFactory("YVaultAssetProxy");
      const tx = wpFactory.deploy(
        vaultV4.address,
        fixture.usdc.address,
        "mock yearn v4",
        "test"
      );
      await expect(tx).to.be.revertedWith("Unsupported Version");
    });

    it("Reserve deposits", async () => {
      // First deposit inits
      await wpV4.reserveDeposit(1e6);
      // Check that we got shares
      let balance = await wpV4.reserveBalances(users[0].address);
      expect(balance).to.be.eq(BigNumber.from(1e6));
      // Do a deposit to convert to shares
      await wpV4.connect(users[1].user).deposit(users[1].address, 1e6);
      console.log(await fixture.usdc.balanceOf(vaultV4.address));
      // We want to change deposit rate
      await fixture.usdc.transfer(vaultV4.address, 5e5);
      // Now we deposit and check the price of deposit
      await wpV4.reserveDeposit(1e6);
      // Check the new balance
      balance = await wpV4.reserveBalances(users[0].address);
      // Magic number from rounding error on deposits
      expect(balance).to.be.eq(BigNumber.from(1857144));
    });

    it("withdraws with the correct ratio", async () => {
      await wpV4.deposit(users[0].address, 1e6);
      // Check that we got shares
      const balance = await wpV4.balanceOf(users[0].address);
      expect(balance).to.be.eq(BigNumber.from(1e6));
      // We want to change withdraw rate
      await fixture.usdc.transfer(vaultV4.address, 5e5);
      // withdraw
      const balanceBefore = await fixture.usdc.balanceOf(users[0].address);
      await wpV4.withdraw(users[0].address, balance, 0);
      const balanceAfter = await fixture.usdc.balanceOf(users[0].address);
      // check the withdraw amount
      expect(balanceAfter.sub(balanceBefore)).to.be.eq(125e4);
    });
  });
});
