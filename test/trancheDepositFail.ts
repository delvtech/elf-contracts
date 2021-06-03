import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import { realisticTestTranche, RealisticTestTranche } from "./helpers/deployer";
import { bnFloatMultiplier, subError } from "./helpers/math";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime, getCurrentTimestamp } from "./helpers/time";
import { getPermitSignature } from "./helpers/signatures";
import { ERC20Permit } from "typechain/ERC20Permit";

const { provider } = waffle;

describe("Tranche", () => {
  let fixture: RealisticTestTranche;
  let user1: Signer;
  let user2: Signer;
  let user1Address: string;
  let expiration: number;
  // 1 million usdc
  const initialBalance = ethers.utils.parseUnits("1", 13);

  before(async () => {
    const time = await getCurrentTimestamp(provider);
    expiration = 1e10 - time;
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts
    fixture = await realisticTestTranche();

    [user1, user2] = await ethers.getSigners();
    user1Address = await user1.getAddress();

    const veryMuch = ethers.utils.parseEther("200000000");
    // Mint for the users
    await fixture.usdc.connect(user1).setBalance(user1Address, veryMuch);
    // Set approvals on the tranche
    await fixture.usdc
      .connect(user1)
      .approve(fixture.tranche.address, veryMuch);
    // Set approvals on the wp
    await fixture.usdc.connect(user1).approve(fixture.wp.address, veryMuch);
    await fixture.usdc.connect(user1).approve(fixture.yusdc.address, veryMuch);
    // Deposit into yearn vault
    await fixture.yusdc.deposit(initialBalance, user1Address);
  });
  after(async () => {
    // revert back to initial state after all tests pass
    await restoreSnapshot(provider);
  });

  describe("Array test", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });

    afterEach(async () => {
      // revert back to initial state after all tests pass
      await restoreSnapshot(provider);
    });

    Array.from(Array(1000).keys()).forEach(() => {
      it("Test random interest rates", async () => {
        const totalLiquidity = bnFloatMultiplier(
          initialBalance.mul(70),
          Math.random()
        );
        await fixture.wp.deposit(user1Address, totalLiquidity);

        const randomInterest = Math.random() * 0.1;
        // set pool interest accumulated to random interest
        await fixture.usdc.transfer(
          fixture.yusdc.address,
          bnFloatMultiplier(await fixture.yusdc.totalAssets(), randomInterest)
        );
        await fixture.tranche
          .connect(user1)
          .deposit(initialBalance.div(100), await user1.getAddress());
        await fixture.tranche
          .connect(user1)
          .deposit(initialBalance, await user1.getAddress());
      });
    });
  });
});
