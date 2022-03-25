import { SwapHelperStruct } from "typechain/ConvexAssetProxy";
import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import { ethers, waffle, network } from "hardhat";

import { ConvexFixtureInterface, loadConvexFixture } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

import { impersonate, stopImpersonating } from "./helpers/impersonate";
import { subError } from "./helpers/math";
import { advanceBlock } from "./helpers/time";

const { provider } = waffle;

describe("Convex Asset Proxy", () => {
  let users: { user: Signer; address: string }[];
  let fixture: ConvexFixtureInterface;
  // address of a large usdc holder to impersonate. 69 million usdc as of block 11860000
  const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";
  let user0LPStartingBalance: BigNumber;
  let user1LPStartingBalance: BigNumber;
  const alchemy_key = "kwjMP-X-Vajdk1ItCfU-56Uaq1wwhamK";

  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // We need to fast forward in time relative to the previous pinned block number
    // The LUSD-3CRV pool was deployed at block 12184843, and our hardhat config currently
    // pins block 11853372
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${alchemy_key}`,
            // block at Mar-23-2022 08:34:43 AM +UTC
            blockNumber: 14441489,
          },
        },
      ],
    });

    const signers = await ethers.getSigners();
    // load all related contracts
    fixture = await loadConvexFixture(signers[0]);

    // begin to populate the user array by assigning each index a signer
    users = signers.map(function (user) {
      return { user, address: "" };
    });

    // finish populating the user array by assigning each index a signer address
    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    impersonate(usdcWhaleAddress);
    const usdcWhale = await ethers.provider.getSigner(usdcWhaleAddress);

    await fixture.usdc.connect(usdcWhale).transfer(users[0].address, 2e11); // 200k usdc
    await fixture.usdc.connect(usdcWhale).transfer(users[1].address, 2e11); // 200k usdc
    await fixture.usdc.connect(usdcWhale).transfer(users[2].address, 2e11); // 200k usdc

    stopImpersonating(usdcWhaleAddress);

    // Let's deposit into Curve Pool to get LUSD-3CRV LP tokens back
    await fixture.usdc
      .connect(users[0].user)
      .approve(fixture.curveZap.address, 10e11);
    await fixture.usdc
      .connect(users[1].user)
      .approve(fixture.curveZap.address, 10e11);
    await fixture.curveZap
      .connect(users[0].user)
      .add_liquidity(fixture.curveMetaPool, [0, 0, 2e11, 0], 0);
    await fixture.curveZap
      .connect(users[1].user)
      .add_liquidity(fixture.curveMetaPool, [0, 0, 2e11, 0], 0);

    user0LPStartingBalance = await fixture.lpToken.balanceOf(users[0].address);
    user1LPStartingBalance = await fixture.lpToken.balanceOf(users[1].address);

    // Approve the wrapped position to access our LP tokens
    await fixture.lpToken
      .connect(users[0].user)
      .approve(fixture.position.address, ethers.constants.MaxUint256);
    await fixture.lpToken
      .connect(users[1].user)
      .approve(fixture.position.address, ethers.constants.MaxUint256);
  });

  // After we reset our state in the fork
  after(async () => {
    await restoreSnapshot(provider);

    // After running all of these tests, reset back to the original pinned block
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${alchemy_key}`,
            blockNumber: 11853372,
          },
        },
      ],
    });
  });

  // Before each we snapshot
  beforeEach(async () => {
    await createSnapshot(provider);
  });
  // After we reset our state in the fork
  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("deposit", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    // After we reset our state in the fork
    afterEach(async () => {
      await restoreSnapshot(provider);
    });

    it("deposits correctly", async () => {
      await fixture.position
        .connect(users[0].user)
        .deposit(users[0].address, user0LPStartingBalance);
      const balance = await fixture.position.balanceOf(users[0].address);
      // Allows a 0.01% conversion error
      expect(balance).to.be.at.least(
        subError(ethers.BigNumber.from(user0LPStartingBalance))
      );
    });

    it("Allows for two deposits correctly", async () => {
      const minimumBalanceLpTokens = user0LPStartingBalance.gt(
        user1LPStartingBalance
      )
        ? user1LPStartingBalance
        : user0LPStartingBalance;

      await fixture.position
        .connect(users[0].user)
        .deposit(users[0].address, minimumBalanceLpTokens);
      await fixture.position
        .connect(users[1].user)
        .deposit(users[1].address, minimumBalanceLpTokens);
      const user0Balance = await fixture.position.balanceOf(users[0].address);
      const user1Balance = await fixture.position.balanceOf(users[1].address);

      // They are the only two depositors and deposit same amount, so they should have same shares
      expect(user0Balance).to.be.eq(user1Balance);
    });

    it("fails to deposit amount greater than available", async () => {
      const tx = fixture.position
        .connect(users[1].user)
        .deposit(
          users[1].address,
          user1LPStartingBalance.add(ethers.constants.WeiPerEther)
        );
      await expect(tx).to.be.reverted;
    });
  });
  describe("withdraw", () => {
    it("withdraws correctly", async () => {
      await fixture.position
        .connect(users[0].user)
        .deposit(users[0].address, user0LPStartingBalance);
      const shareBalance = await fixture.position.balanceOf(users[0].address);
      await fixture.position
        .connect(users[0].user)
        .withdraw(users[0].address, shareBalance, 0);
      expect(await fixture.position.balanceOf(users[0].address)).to.equal(0);
      // Should get all their LP tokens back
      expect(await fixture.lpToken.balanceOf(users[0].address)).to.be.eq(
        user0LPStartingBalance
      );
    });
    it("fails to withdraw more shares than in balance", async () => {
      // withdraw 10 shares from user with balance 0
      const tx = fixture.position
        .connect(users[4].user)
        .withdraw(users[4].address, 10, 0);
      await expect(tx).to.be.reverted;
    });
    // test withdrawUnderlying to verify _underlying calculation
    it("withdrawUnderlying correctly", async () => {
      await fixture.position
        .connect(users[0].user)
        .deposit(users[0].address, user0LPStartingBalance);
      const shareBalance = await fixture.position.balanceOf(users[0].address);
      // Withdraw to get 1/2 LP tokens sent to user2
      await fixture.position
        .connect(users[0].user)
        .withdrawUnderlying(users[2].address, shareBalance.div(2), 0);
      expect(await fixture.position.balanceOf(users[2].address)).to.equal(0);
      expect(await fixture.lpToken.balanceOf(users[2].address)).to.equal(
        shareBalance.div(2)
      );
    });
  });
  describe("rewards", () => {
    it("Harvests rewards correctly", async () => {
      await fixture.position
        .connect(users[0].user)
        .deposit(users[0].address, user0LPStartingBalance);

      // Now simulate passage of time to accrue CRV, CVX rewards
      const blocks_per_day = 5760;
      const days_to_simulate = 3;
      for (let i = 0; i < blocks_per_day * days_to_simulate; i++) {
        await advanceBlock(provider);
      }

      // Now let the owner (user[0]) approve user 4 as an authorized harvester
      await fixture.position.connect(users[0].user).authorize(users[4].address);

      // Now check deposited token balance before & after for our wrapped position
      // Also check balance of LP token for harvester to ensure they received a bounty
      const stakedRewardTokenBalanceBefore =
        await fixture.rewardsContract.balanceOf(fixture.position.address);
      const harvesterLpTokenBalanceBefore = await fixture.lpToken.balanceOf(
        users[4].address
      );

      // Now trigger a harvest
      // First, create our struct helpers for crv, cvx
      const crvHelper: SwapHelperStruct = {
        token: fixture.crv.address,
        deadline: ethers.constants.MaxUint256,
        amountOutMinimum: 0,
      };
      const cvxHelper: SwapHelperStruct = {
        token: fixture.cvx.address,
        deadline: ethers.constants.MaxUint256,
        amountOutMinimum: 0,
      };

      await fixture.position
        .connect(users[4].user)
        .harvest([crvHelper, cvxHelper]);

      // Now we should have more convexDeposit Token
      const stakedRewardTokenBalanceAfter =
        await fixture.rewardsContract.balanceOf(fixture.position.address);
      expect(stakedRewardTokenBalanceAfter).to.be.gt(
        stakedRewardTokenBalanceBefore
      );

      // Harvester should have received a bounty
      const harvesterLpTokenBalanceAfter = await fixture.lpToken.balanceOf(
        users[4].address
      );
      expect(harvesterLpTokenBalanceAfter).to.be.gt(
        harvesterLpTokenBalanceBefore
      );
    });

    it("fails for unauthorized user", async () => {
      const crvHelper: SwapHelperStruct = {
        token: fixture.crv.address,
        deadline: ethers.constants.MaxUint256,
        amountOutMinimum: 0,
      };
      const cvxHelper: SwapHelperStruct = {
        token: fixture.cvx.address,
        deadline: ethers.constants.MaxUint256,
        amountOutMinimum: 0,
      };

      const tx = fixture.position
        .connect(users[4].user)
        .harvest([crvHelper, cvxHelper]);
      await expect(tx).to.be.reverted;
    });
  });
});
