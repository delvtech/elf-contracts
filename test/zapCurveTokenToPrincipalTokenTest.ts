import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { IERC20 } from "typechain/IERC20";
import { UserProxy } from "typechain/UserProxy";
import { Vault } from "typechain/Vault";
import { ZapCurveTokenToPrincipalToken } from "typechain/ZapCurveTokenToPrincipalToken";
import { ZERO } from "./helpers/constants";
import {
  constructZapInArgs,
  constructZapOutArgs,
  deploy,
  mintPrincipalTokens,
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
  let proxy: UserProxy;
  let blankAddress: string;

  before(async () => {
    await createSnapshot(provider);

    users = ((await ethers.getSigners()) as Signer[]).map((user) => ({
      user,
      address: "",
    }));

    // Address we can send funds to
    blankAddress = ethers.Wallet.createRandom().address;

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
      proxy,
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
            ETH: ethers.utils.parseEther("1"),
          },
          balancerVault,
          users[1].address
        );
      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveIn(info, zap, childZaps, {
          value: ethers.utils.parseEther("1"),
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

    it.only("should swap ePyvcrvSTETH to ETH", async () => {
      const ePyvcrvSTETHAmount = await mintPrincipalTokens(
        ePyvcrvSTETH,
        proxy,
        users[1].address
      );

      const { info, zap, childZap } = await constructZapOutArgs(
        ePyvcrvSTETH,
        "ETH",
        ePyvcrvSTETHAmount,
        balancerVault,
        blankAddress
      );

      await zapCurveTokenToPrincipalToken
        .connect(users[1].user)
        .zapCurveOut(info, zap, childZap);

      const returnedTokenAmount = await provider.getBalance(blankAddress);

      console.log(ethers.utils.formatEther(ePyvcrvSTETHAmount));
      console.log(ethers.utils.formatEther(returnedTokenAmount));
    });

    it("should swap stETH for ePyvcrvSTETH", async () => {
      await createSnapshot(provider);

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

    // it("should swap ePyvcrvSTETH to stETH", async () => {
    //   const ePyvcrvSTETHAmount = await ePyvcrvSTETH.token.balanceOf(
    //     users[1].address
    //   );

    //   const { info, zap, childZap } = await constructZapOutArgs(
    //     ePyvcrvSTETH,
    //     "stETH",
    //     ePyvcrvSTETHAmount,
    //     balancerVault,
    //     blankAddress
    //   );

    //   await zapCurveTokenToPrincipalToken
    //     .connect(users[1].user)
    //     .zapCurveOut(info, zap, childZap);

    //   const returnedTokenAmount = await (
    //     ePyvcrvSTETH.baseToken.roots[1].token as IERC20
    //   ).balanceOf(blankAddress);

    //   console.log(ethers.utils.formatEther(ePyvcrvSTETHAmount));
    //   console.log(ethers.utils.formatEther(returnedTokenAmount));

    //   await restoreSnapshot(provider);
    // });

    it("should swap stETH & ETH for ePyvcrvSTETH", async () => {
      await createSnapshot(provider);
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
      await restoreSnapshot(provider);
    });
  });

  describe("USDT:WBTC:WETH -> ePyvcrv3crypto", () => {
    it("should swap USDT for ePyvcrv3crypto", async () => {
      await createSnapshot(provider);
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

    // it("should swap ePyvcrv3crypto to USDT", async () => {
    //   const ePyvcrv3cryptoAmount = await ePyvcrv3crypto.token.balanceOf(
    //     users[1].address
    //   );

    //   const { info, zap, childZap } = await constructZapOutArgs(
    //     ePyvcrv3crypto,
    //     "USDT",
    //     ePyvcrv3cryptoAmount,
    //     balancerVault,
    //     blankAddress
    //   );

    //   await zapCurveTokenToPrincipalToken
    //     .connect(users[1].user)
    //     .zapCurveOut(info, zap, childZap);

    //   const returnedTokenAmount = await (
    //     ePyvcrv3crypto.baseToken.roots[0].token as IERC20
    //   ).balanceOf(blankAddress);

    //   console.log(ethers.utils.formatEther(ePyvcrv3cryptoAmount));
    //   console.log(ethers.utils.formatUnits(returnedTokenAmount, 6));

    //   await restoreSnapshot(provider);
    // });

    it("should swap WBTC for ePyvcrv3crypto", async () => {
      await createSnapshot(provider);
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

    // it("should swap ePyvcrv3crypto to WBTC", async () => {
    //   const ePyvcrv3cryptoAmount = await ePyvcrv3crypto.token.balanceOf(
    //     users[1].address
    //   );

    //   const { info, zap, childZap } = await constructZapOutArgs(
    //     ePyvcrv3crypto,
    //     "WBTC",
    //     ePyvcrv3cryptoAmount,
    //     balancerVault,
    //     blankAddress
    //   );

    //   await zapCurveTokenToPrincipalToken
    //     .connect(users[1].user)
    //     .zapCurveOut(info, zap, childZap);

    //   const returnedTokenAmount = await (
    //     ePyvcrv3crypto.baseToken.roots[1].token as IERC20
    //   ).balanceOf(blankAddress);

    //   console.log(ethers.utils.formatEther(ePyvcrv3cryptoAmount));
    //   console.log(ethers.utils.formatUnits(returnedTokenAmount, 8));

    //   await restoreSnapshot(provider);
    // });

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

    // it("should swap ePyvcrv3crypto to WETH", async () => {
    //   const ePyvcrv3cryptoAmount = await ePyvcrv3crypto.token.balanceOf(
    //     users[1].address
    //   );

    //   const { info, zap, childZap } = await constructZapOutArgs(
    //     ePyvcrv3crypto,
    //     "WETH",
    //     ePyvcrv3cryptoAmount,
    //     balancerVault,
    //     blankAddress
    //   );

    //   await zapCurveTokenToPrincipalToken
    //     .connect(users[1].user)
    //     .zapCurveOut(info, zap, childZap);

    //   const returnedTokenAmount = await (
    //     (ePyvcrv3crypto.baseToken.roots[2] as any).token as IERC20
    //   ).balanceOf(blankAddress);

    //   console.log(ethers.utils.formatEther(ePyvcrv3cryptoAmount));
    //   console.log(ethers.utils.formatEther(returnedTokenAmount));

    //   await restoreSnapshot(provider);
    // });

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
