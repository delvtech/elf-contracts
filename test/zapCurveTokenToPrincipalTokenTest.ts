import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { Vault } from "typechain/Vault";
import { ZapCurveTokenToPrincipalToken } from "typechain/ZapCurveTokenToPrincipalToken";
import { ZERO } from "./helpers/constants";
import {
  constructZapInArgs,
  //constructZapOutArgs,
  deploy,
  PrincipalTokenCurveTrie,
} from "./helpers/deployZapCurveTokenToPrincipalToken";
import { calcBigNumberPercentage } from "./helpers/math";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

const ptOffsetTolerancePercentage = 0.1;

describe.only("ZapCurveTokenToPrincpalToken", () => {
  let users: { user: Signer; address: string }[];

  let zapCurveTokenToPrincipalToken: ZapCurveTokenToPrincipalToken;
  let ePyvcrvSTETH: PrincipalTokenCurveTrie;
  let ePyvcrv3crypto: PrincipalTokenCurveTrie;
  let ePyvCurveLUSD: PrincipalTokenCurveTrie;
  let balancerVault: Vault;

  before(async () => {
    await createSnapshot(provider);

    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return { user, address: "" };
    });

    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    ({
      zapCurveTokenToPrincipalToken,
      balancerVault,
      ePyvcrvSTETH,
      ePyvcrv3crypto,
      ePyvCurveLUSD,
    } = await deploy(users[1]));
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

  describe("ETH:STETH <-> ePyvcrvSTETH", () => {
    it("should swap ETH for ePyvcrvSTETH", async () => {
      await createSnapshot(provider);
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvcrvSTETH,
          {
            ETH: ethers.utils.parseEther("100"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps, {
          value: ethers.utils.parseEther("100"),
        });
      const returnedPrincipalTokenAmount = await ePyvcrvSTETH.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });

    // it.only("should swap ePyvcrvSTETH to ETH", async () => {
    //   const ePyvcrvSTETHAmount = await ePyvcrvSTETH.token.balanceOf(
    //     users[1].address
    //   );
    //   console.log(
    //     "ePyvcrvSTETHAmount:",
    //     ethers.utils.formatEther(ePyvcrvSTETHAmount)
    //   );

    //   const { info: infoOut, zap: zapOut } = await constructZapOutArgs(
    //     ePyvcrvSTETH,
    //     "ETH",
    //     ePyvcrvSTETHAmount,
    //     balancerVault,
    //     users[1].address
    //   );

    //   await zapCurveTokenToPrincipalToken
    //     .connect(users[1].user)
    //     .zapCurveOut(infoOut, zapOut);

    //   // const { info, zap, childZaps, expectedPrincipalTokenAmount } =
    //   //   await constructZapInArgs(
    //   //     ePyvcrvSTETH,
    //   //     {
    //   //       ETH: ethers.utils.parseEther("100"),
    //   //     },
    //   //     balancerVault,
    //   //     users[1].address
    //   //   );
    //   // await zapCurveTokenToPrincipalToken
    //   //   .connect(users[1].user)
    //   //   .zapCurveIn(info, zap, childZaps, {
    //   //     value: ethers.utils.parseEther("100"),
    //   //   });
    //   // const returnedPrincipalTokenAmount = await ePyvcrvSTETH.token.balanceOf(
    //   //   users[1].address
    //   // );
    //   // const diff = returnedPrincipalTokenAmount.sub(
    //   //   expectedPrincipalTokenAmount
    //   // );
    //   // const allowedOffset = calcBigNumberPercentage(
    //   //   returnedPrincipalTokenAmount,
    //   //   ptOffsetTolerancePercentage
    //   // );
    //   // expect(diff.gte(ZERO)).to.be.true;
    //   // expect(diff.lt(allowedOffset)).to.be.true;

    //   await restoreSnapshot(provider);
    // });

    it("should swap stETH for ePyvcrvSTETH", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvcrvSTETH,
          {
            stETH: ethers.utils.parseEther("100"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvcrvSTETH.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });

    it("should swap stETH & ETH for ePyvcrvSTETH", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvcrvSTETH,
          {
            ETH: ethers.utils.parseEther("100"),
            stETH: ethers.utils.parseEther("100"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps, {
          value: ethers.utils.parseEther("100"),
        });
      const returnedPrincipalTokenAmount = await ePyvcrvSTETH.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
  });

  describe("USDT:WBTC:WETH -> ePyvcrv3crypto", () => {
    it("should swap USDT for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvcrv3crypto,
          {
            USDT: ethers.utils.parseUnits("5000", 6),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvcrv3crypto.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap WBTC for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvcrv3crypto,
          {
            WBTC: ethers.utils.parseUnits("0.2", 8),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvcrv3crypto.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap WETH for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvcrv3crypto,
          {
            WETH: ethers.utils.parseEther("2"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvcrv3crypto.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap WBTC,USDT & WETH for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvcrv3crypto,
          {
            WETH: ethers.utils.parseEther("2"),
            WBTC: ethers.utils.parseUnits("0.2", 8),
            USDT: ethers.utils.parseUnits("5000", 6),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvcrv3crypto.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        1
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
  });

  describe("LUSD:3Crv:DAI:USDC:USDT -> ePyvCurveLUSD", () => {
    it("should swap DAI for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvCurveLUSD,
          {
            DAI: ethers.utils.parseEther("5000"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvCurveLUSD.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap USDC for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvCurveLUSD,
          {
            USDC: ethers.utils.parseUnits("5000", 6),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvCurveLUSD.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap USDT for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvCurveLUSD,
          {
            USDT: ethers.utils.parseUnits("5000", 6),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvCurveLUSD.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap LUSD for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvCurveLUSD,
          {
            LUSD: ethers.utils.parseEther("5000"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvCurveLUSD.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap 3Crv for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvCurveLUSD,
          {
            ["3Crv"]: ethers.utils.parseEther("5000"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvCurveLUSD.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap LUSD and DAI for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvCurveLUSD,
          {
            LUSD: ethers.utils.parseEther("5000"),
            DAI: ethers.utils.parseEther("5000"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvCurveLUSD.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap 3Crv and DAI for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvCurveLUSD,
          {
            ["3Crv"]: ethers.utils.parseEther("5000"),
            DAI: ethers.utils.parseEther("5000"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvCurveLUSD.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
    it("should swap LUSD, DAI, USDC, USDT & ThreeCrv for ePyvcrv3crypto", async () => {
      const { info, zap, childZaps, expectedPrincipalTokenAmount } =
        await constructZapInArgs(
          ePyvCurveLUSD,
          {
            ["3Crv"]: ethers.utils.parseEther("5000"),
            DAI: ethers.utils.parseEther("5000"),
            USDC: ethers.utils.parseUnits("5000", 6),
            USDT: ethers.utils.parseUnits("5000", 6),
            LUSD: ethers.utils.parseEther("5000"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps);
      const returnedPrincipalTokenAmount = await ePyvCurveLUSD.token.balanceOf(
        users[1].address
      );
      const diff = returnedPrincipalTokenAmount.sub(
        expectedPrincipalTokenAmount
      );
      const allowedOffset = calcBigNumberPercentage(
        returnedPrincipalTokenAmount,
        ptOffsetTolerancePercentage
      );
      expect(diff.gte(ZERO)).to.be.true;
      expect(diff.lt(allowedOffset)).to.be.true;
    });
  });
});
