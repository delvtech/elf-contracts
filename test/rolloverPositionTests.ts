import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import { FixtureInterface, loadFixture } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime, getCurrentTimestamp } from "./helpers/time";

import { TestBalancerVault } from "typechain/TestBalancerVault";
import { Tranche } from "typechain/Tranche";
import { RolloverAssetProxy } from "typechain/RolloverAssetProxy";
import { TestERC20 } from "typechain/TestERC20";

const { provider } = waffle;

describe("Rollover Wrapped Position", () => {
  let users: { user: Signer; address: string }[];
  let fixture: FixtureInterface;
  let vault: TestBalancerVault;
  let secondTranche: Tranche;
  let rollover: RolloverAssetProxy;
  let firstTermBalID: string;
  let secondTermBalID: string;
  let firstExpiry: BigNumber;
  let secondExpiry: BigNumber;
  let lp: TestERC20;
  let yieldToken: TestERC20;

  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts
    fixture = await loadFixture();
    // begin to populate the user array by assigning each index a signer
    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return { user, address: "" };
    });
    // Load the addresses
    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    // Make an initial deposit in the aypool contract
    // This prevents a div by zero reversion in several cases
    await fixture.usdc.mint(users[0].address, 100);
    await fixture.usdc.approve(fixture.yusdc.address, 100);
    await fixture.yusdc.deposit(100, users[0].address);

    // We deploy the test vault
    const deployerVault = await ethers.getContractFactory(
      "TestBalancerVault",
      users[0].user
    );
    vault = await deployerVault.deploy();
    // We deploy an extra tranche
    firstExpiry = await fixture.tranche.unlockTimestamp();
    secondExpiry = firstExpiry.add(864000);

    // Get typesafe deployer
    const deployerTranche = await ethers.getContractFactory(
      "Tranche",
      users[0].user
    );
    await fixture.trancheFactory.deployTranche(
      secondExpiry,
      fixture.yusdc.address
    );
    const eventFilter = fixture.trancheFactory.filters.TrancheCreated(
      null,
      null,
      secondExpiry
    );
    const events = await fixture.trancheFactory.queryFilter(eventFilter);
    const trancheAddress = events[0] && events[0].args && events[0].args[0];
    secondTranche = deployerTranche.attach(trancheAddress);

    // Deploy the rollover wrapped position
    const deployerRollover = await ethers.getContractFactory(
      "RolloverAssetProxy",
      users[0].user
    );
    rollover = await deployerRollover.deploy(
      users[0].address,
      users[1].address,
      vault.address,
      1e6,
      1e6,
      86400,
      fixture.usdc.address,
      "Element",
      "Rollover"
    );
    // Register the rollovers in the fake balancer vault
    await vault.makePool(fixture.usdc.address, fixture.tranche.address);
    firstTermBalID =
      "0x0000000000000000000000000000000000000000000000000000000000000001";
    await vault.makePool(fixture.usdc.address, secondTranche.address);
    secondTermBalID =
      "0x0000000000000000000000000000000000000000000000000000000000000002";

    // finish populating the user array by assigning each index a signer address
    // and approve 6e6 usdc to the position contract for each address
    await Promise.all(
      users.map(async (userInfo) => {
        await fixture.usdc.mint(userInfo.address, 6e6);
        await fixture.usdc
          .connect(userInfo.user)
          .approve(rollover.address, 12e6);
      })
    );
  });

  after(async () => {
    await restoreSnapshot(provider);
  });

  describe("Function permission-ing", async () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });

    it("Only lets governance set min wait time", async () => {
      const tx = rollover.connect(users[1].user).setMinWaitTime(1);
      await expect(tx).to.be.revertedWith("Sender not owner");

      await rollover.setMinWaitTime(100);
      expect(await rollover.minWaitTime()).to.be.eq(100);
    });

    it("Only let's governance set the balancer vault", async () => {
      const tx = rollover.connect(users[1].user).setBalancer(users[0].address);
      await expect(tx).to.be.revertedWith("Sender not owner");

      await rollover.setBalancer(users[0].address);
      expect(await rollover.balancer()).to.be.eq(users[0].address);
    });

    it("Only allows manager to register a new term", async () => {
      const tx = rollover.registerNewTerm(
        users[0].address,
        "0xa17cc7e070729d48fab5bd1e13c327506527da19efce661f456d80978e011ff0"
      );
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });

    it("Only allows manager to start a new term", async () => {
      const tx = rollover.newTerm(0, {
        assets: [users[0].address, users[0].address],
        maxAmountsIn: [0, 0],
        userData: "0x",
        fromInternalBalance: false,
      });
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });

    it("Only allows manager to end a term", async () => {
      const tx = rollover.exitTerm({
        assets: [users[0].address, users[0].address],
        minAmountsOut: [0, 0],
        userData: "0x",
        toInternalBalance: false,
      });
      await expect(tx).to.be.revertedWith("Sender not Authorized");
    });
  });

  describe("Settlement period deposits and withdraws", async () => {
    // We intentionally expect these to run in order because their configuration will be
    // very complex.

    it("Preforms first and second deposits correctly", async () => {
      // The first deposit is unique because it triggers a zero total supply case
      await rollover.deposit(users[0].address, 1e6);
      // After we should have 1e6 shares
      expect(await rollover.balanceOf(users[0].address)).to.be.eq(
        BigNumber.from(1e6)
      );
      // The second deposit tests ratio logic
      await rollover.deposit(users[1].address, 2e6);
      // After we should have 1e6 shares
      expect(await rollover.balanceOf(users[1].address)).to.be.eq(
        BigNumber.from(2e6)
      );
    });

    it("Allows rollover registration", async () => {
      await rollover
        .connect(users[1].user)
        .registerNewTerm(fixture.tranche.address, firstTermBalID);
    });

    it("Blocks an early rollover", async () => {
      const tx = rollover.connect(users[1].user).newTerm(15e5, {
        assets: [fixture.usdc.address, fixture.tranche.address],
        maxAmountsIn: [15e5, 15e5],
        userData: "0x",
        fromInternalBalance: false,
      });
      await expect(tx).to.be.revertedWith("Rollover before time lock");
    });

    it("Blocks a rollover which does not create max LP tokens", async () => {
      await advanceTime(
        provider,
        (await rollover.minWaitTime()).toNumber() + 1
      );
      let tx = rollover.connect(users[1].user).newTerm(3e6, {
        assets: [fixture.usdc.address, fixture.tranche.address],
        maxAmountsIn: [0, 0],
        userData: "0x",
        fromInternalBalance: false,
      });
      await expect(tx).to.be.revertedWith("Manager did not fully rollover PT");
      tx = rollover.connect(users[1].user).newTerm(1e6, {
        assets: [fixture.usdc.address, fixture.tranche.address],
        maxAmountsIn: [5e5, 5e5],
        userData: "0x",
        fromInternalBalance: false,
      });
      await expect(tx).to.be.revertedWith(
        "Manager did not fully rollover base"
      );
    });

    it("Allows properly timed first rollover", async () => {
      await advanceTime(
        provider,
        (await rollover.minWaitTime()).toNumber() + 1
      );
      await rollover.connect(users[1].user).newTerm(15e5, {
        assets: [fixture.usdc.address, fixture.tranche.address],
        maxAmountsIn: [15e5, 15e5],
        userData: "0x",
        fromInternalBalance: false,
      });
      const deployerErc20 = await ethers.getContractFactory(
        "TestERC20",
        users[0].user
      );
      const lpAddress = await vault.lpTokens(firstTermBalID);
      lp = deployerErc20.attach(lpAddress);
      yieldToken = deployerErc20.attach(await fixture.tranche.interestToken());
      expect(await lp.balanceOf(rollover.address)).to.be.eq(
        BigNumber.from(15e5)
      );
      expect(await yieldToken.balanceOf(rollover.address)).to.be.eq(
        BigNumber.from(15e5)
      );
      expect(await rollover.ytSupply()).to.be.eq(15e5);
      expect(await rollover.lpSupply()).to.be.eq(15e5);
    });

    it("Allows a proportional withdraw in committed period", async () => {
      await rollover.withdraw(users[3].address, 2e5, 0);
      expect(await lp.balanceOf(users[3].address)).to.be.eq(1e5);
      expect(await yieldToken.balanceOf(users[3].address)).to.be.eq(1e5);
    });

    it("Does not allow a regular deposit in committed period", async () => {
      // Note that the deposit method transfers JUST the underlying token and
      // so is expected to be broken in this way
      const tx = rollover.deposit(users[0].address, 1e6);
      await expect(tx).to.be.revertedWith("No deposit");
    });

    // NOTE - This test and the next must be executed in order.
    it("Does not allow a non proportional deposit in committed period", async () => {
      await lp.connect(users[3].user).transfer(rollover.address, 1e5);
      const tx = rollover.prefundedDeposit(users[0].address);
      await expect(tx).to.be.revertedWith("Incorrect Ratio");
    });

    it("Allows a proportional deposit in committed period", async () => {
      // Note - the necessary LP transfer is in the previous test
      await yieldToken.connect(users[3].user).transfer(rollover.address, 1e5);
      await rollover.prefundedDeposit(users[0].address);
      // Note this constant is the same as the original balance
      expect(await rollover.balanceOf(users[0].address)).to.be.eq(1e6);
    });
  });
});
