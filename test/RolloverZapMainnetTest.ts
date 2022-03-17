import { expect } from "chai";
import { BigNumber, BigNumberish, Signer } from "ethers";
import { ethers, waffle } from "hardhat";

import {
  UsdcPoolRolloverZapMainnetInterface,
  loadUsdcPoolRolloverZapMainnetFixture,
} from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime, getCurrentTimestamp } from "./helpers/time";
import { impersonate, stopImpersonating } from "./helpers/impersonate";
import { IERC20__factory } from "typechain/factories/IERC20__factory";

import { TestBalancerVault } from "typechain/TestBalancerVault";
import { Tranche } from "typechain/Tranche";
import { RolloverAssetProxy } from "typechain/RolloverAssetProxy";
import { RolloverZap } from "typechain/RolloverZap";
import { setBlock } from "test/helpers/forking";

import { TestERC20 } from "typechain/TestERC20";
import { IERC20 } from "typechain/IERC20";

const { provider } = waffle;

describe("Rollover Zap Mainnet Test", () => {
  let users: { user: Signer; address: string }[];
  let fixture: UsdcPoolRolloverZapMainnetInterface;
  let secondTranche: Tranche;
  let rollover: RolloverAssetProxy;
  let zap: RolloverZap;
  let lp: TestERC20;
  let yieldToken: TestERC20;
  let initBlock: number;
  let poolId: string;
  let rolloverYt: IERC20;
  let internalYt: IERC20;
  let balancerLp: IERC20;
  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    initBlock = await provider.getBlockNumber();
    setBlock(14398000);

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
    const [signer] = await ethers.getSigners();

    const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";
    // Deploy the rollover wrapped position
    const deployerRollover = await ethers.getContractFactory(
      "RolloverAssetProxy",
      users[0].user
    );
    // Deploy the rollover wrapped position
    const deployerZap = await ethers.getContractFactory(
      "RolloverZap",
      users[0].user
    );
    // deploy rollover on USDC tranche
    rollover = await deployerRollover.deploy(
      users[0].address,
      users[0].address,
      "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
      1e6,
      1e6,
      1,
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "Element",
      "Rollover"
    );
    zap = await deployerZap.deploy(
      "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
      users[0].address,
      0,
      0
    );
    // load all related contracts
    fixture = await loadUsdcPoolRolloverZapMainnetFixture(rollover.address);

    // initialize tranche
    poolId =
      "0x7edde0cb05ed19e03a9a47cd5e53fc57fde1c80c0002000000000000000000c8";
    await rollover
      .connect(users[0].user)
      .registerNewTerm(fixture.tranche.address, poolId);

    impersonate(usdcWhaleAddress);
    const usdcWhale = ethers.provider.getSigner(usdcWhaleAddress);

    await fixture.usdc.connect(usdcWhale).transfer(users[0].address, 2e11); // 200k usdc

    stopImpersonating(usdcWhaleAddress);
    await fixture.usdc
      .connect(users[0].user)
      .approve(fixture.position.address, 2e11); // 200k usdc
    await fixture.usdc.approve(zap.address, 2e11);

    const rolloverYtAddress = await fixture.trancheRollover.interestToken();
    const internalYtAddress = await fixture.tranche.interestToken();

    rolloverYt = IERC20__factory.connect(rolloverYtAddress, signer);
    internalYt = IERC20__factory.connect(internalYtAddress, signer);
    balancerLp = IERC20__factory.connect(
      "0x7edde0cb05ed19e03a9a47cd5e53fc57fde1c80c",
      signer
    );

    await zap.tokenApproval(
      [fixture.usdc.address, fixture.usdc.address, fixture.tranche.address],
      [
        "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
        fixture.tranche.address,
        "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
      ]
    );
  });

  after(async () => {
    await restoreSnapshot(provider);
    setBlock(initBlock);
  });
  // NOTE: individual test cases are dependant on previous, snapshot only taken for describe block
  describe("Deposit", async () => {
    const depositAmount = 1e10;
    const depositRatio = 0.98844;
    const poolRatio = 0.45515;
    const totalRatio = poolRatio / depositRatio;
    const split = Math.floor((depositAmount * totalRatio) / (1 + totalRatio));
    const lp_deposit: BigNumberish[] = [
      Math.floor(split * depositRatio),
      depositAmount - split,
    ];
    before(async () => {
      await createSnapshot(provider);
      // deposit an amount in settlement
      await zap.deposit({
        balancerPoolID: poolId,
        request: {
          assets: [users[0].address, users[0].address],
          maxAmountsIn: [0, 0],
          userData: "0x",
          fromInternalBalance: false,
        },
        rolloverTranche: fixture.trancheRollover.address,
        token: fixture.usdc.address,
        totalAmount: depositAmount,
        depositAmount: depositAmount,
        receiver: users[1].address,
        permitCallData: [],
      });

      // move to out of settlement period
      // deposit amount n = (xr/r+1) ~= 3,451,653,228
      // remainder = 6,548,346,772

      await rollover.newTerm(split, {
        assets: [fixture.tranche.address, fixture.usdc.address],
        maxAmountsIn: [Math.floor(split * depositRatio), depositAmount - split],
        userData: ethers.utils.defaultAbiCoder.encode(
          ["uint256[]"],
          [lp_deposit]
        ),
        fromInternalBalance: false,
      });
    });
    after(async () => {
      await restoreSnapshot(provider);
    });
    it("deposits directly into the tranche during settlement period", async () => {
      const userPtBalance = await fixture.trancheRollover.balanceOf(
        users[1].address
      );
      const uesrYtBalance = await rolloverYt.balanceOf(users[1].address);

      expect(userPtBalance).to.eq(depositAmount);
      expect(uesrYtBalance).to.eq(depositAmount);
    });
    it("deposit, non-settlement. Not enough YT to satisfy ratio. YT deposited == YT in contract", async () => {
      let userPtBalance = await fixture.trancheRollover.balanceOf(
        users[0].address
      );
      let uesrYtBalance = await rolloverYt.balanceOf(users[0].address);

      await zap.deposit({
        balancerPoolID: poolId,
        request: {
          assets: [fixture.tranche.address, fixture.usdc.address],
          maxAmountsIn: [
            Math.floor(split * depositRatio),
            depositAmount - split,
          ],
          userData: ethers.utils.defaultAbiCoder.encode(
            ["uint256[]"],
            [lp_deposit]
          ),
          fromInternalBalance: false,
        },
        rolloverTranche: fixture.trancheRollover.address,
        token: fixture.usdc.address,
        totalAmount: depositAmount,
        depositAmount: split,
        receiver: users[0].address,
        permitCallData: [],
      });

      const ytBalance = await internalYt.balanceOf(zap.address);
      const ptBalance = await fixture.tranche.balanceOf(zap.address);
      const usdcBalance = await fixture.usdc.balanceOf(zap.address);
      const lpBalance = await balancerLp.balanceOf(zap.address);

      expect(ytBalance).to.eq(0);
      expect(ptBalance).to.eq(0);
      expect(usdcBalance).to.eq(0);
      expect(lpBalance).to.eq(0);

      userPtBalance = await fixture.trancheRollover.balanceOf(users[0].address);
      uesrYtBalance = await rolloverYt.balanceOf(users[0].address);

      // new WP without acc interest. so if YT / PT == depositAmount tes is successful
      expect(userPtBalance).to.eq(depositAmount);
      expect(uesrYtBalance).to.eq(depositAmount);
    });
    it("second deposit, non-settlement. not enough YT to satisfy ratio", async () => {
      let userPtBalance = await fixture.trancheRollover.balanceOf(
        users[0].address
      );
      let uesrYtBalance = await rolloverYt.balanceOf(users[0].address);

      await zap.deposit({
        balancerPoolID: poolId,
        request: {
          assets: [fixture.tranche.address, fixture.usdc.address],
          maxAmountsIn: [
            Math.floor(split * depositRatio),
            depositAmount - split,
          ],
          userData: ethers.utils.defaultAbiCoder.encode(
            ["uint256[]"],
            [lp_deposit]
          ),
          fromInternalBalance: false,
        },
        rolloverTranche: fixture.trancheRollover.address,
        token: fixture.usdc.address,
        totalAmount: depositAmount,
        depositAmount: split,
        receiver: users[2].address,
        permitCallData: [],
      });

      const ytBalance = await internalYt.balanceOf(zap.address);
      const ptBalance = await fixture.tranche.balanceOf(zap.address);
      const usdcBalance = await fixture.usdc.balanceOf(zap.address);
      const lpBalance = await balancerLp.balanceOf(zap.address);

      expect(ytBalance).to.eq(0);
      expect(ptBalance).to.eq(0);
      expect(usdcBalance).to.eq(0);
      expect(lpBalance).to.eq(0);

      userPtBalance = await fixture.trancheRollover.balanceOf(users[2].address);
      uesrYtBalance = await rolloverYt.balanceOf(users[2].address);

      // new WP without acc interest. so if YT / PT == depositAmount tes is successful
      expect(userPtBalance).to.eq(depositAmount);
      expect(uesrYtBalance).to.eq(depositAmount);
    });
    it("final deposit, non-settlement. enough YT to satisfy ratio", async () => {
      // we mess with the ratio a bit to make the test case enter the path.
      // This will give us slightly less principal tokens so we
      // approximate the expectation in the end
      const depositAmount = 1e10;
      const depositRatio = 0.98844;
      const poolRatio = 0.4552;
      const totalRatio = poolRatio / depositRatio;
      const split = Math.floor((depositAmount * totalRatio) / (1 + totalRatio));
      const lp_deposit: BigNumberish[] = [
        Math.floor(split * depositRatio),
        depositAmount - split,
      ];
      let userPtBalance = await fixture.trancheRollover.balanceOf(
        users[0].address
      );
      let uesrYtBalance = await rolloverYt.balanceOf(users[0].address);

      await zap.deposit({
        balancerPoolID: poolId,
        request: {
          assets: [fixture.tranche.address, fixture.usdc.address],
          maxAmountsIn: [
            Math.floor(split * depositRatio),
            depositAmount - split,
          ],
          userData: ethers.utils.defaultAbiCoder.encode(
            ["uint256[]"],
            [lp_deposit]
          ),
          fromInternalBalance: false,
        },
        rolloverTranche: fixture.trancheRollover.address,
        token: fixture.usdc.address,
        totalAmount: depositAmount,
        depositAmount: split,
        receiver: users[3].address,
        permitCallData: [],
      });

      const ytBalance = await internalYt.balanceOf(zap.address);
      const ptBalance = await fixture.tranche.balanceOf(zap.address);
      const usdcBalance = await fixture.usdc.balanceOf(zap.address);
      const lpBalance = await balancerLp.balanceOf(zap.address);

      expect(ytBalance).to.eq(0);
      expect(ptBalance).to.eq(0);
      expect(usdcBalance).to.eq(0);
      expect(lpBalance).to.eq(0);

      userPtBalance = await fixture.trancheRollover.balanceOf(users[3].address);
      uesrYtBalance = await rolloverYt.balanceOf(users[3].address);

      // approximate the equals here since we messed with the ratio to force the test case
      expect(userPtBalance.add(ethers.BigNumber.from(10000000))).to.gt(
        depositAmount
      );
      expect(uesrYtBalance.add(ethers.BigNumber.from(10000000))).to.gt(
        depositAmount
      );
    });
  });
});
