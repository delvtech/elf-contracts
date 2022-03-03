import { expect } from "chai";
import { zeroAddress } from "ethereumjs-util";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { ERC20Permit__factory } from "typechain/factories/ERC20Permit__factory";
import { ERC20__factory } from "typechain/factories/ERC20__factory";
import { Vault__factory } from "typechain/factories/Vault__factory";
import { ZapSwapCurve__factory } from "typechain/factories/ZapSwapCurve__factory";
import {
  ZapCurveLpInStruct,
  ZapCurveLpOutStruct,
  ZapInInfoStruct,
  ZapOutInfoStruct,
  ZapSwapCurve,
} from "typechain/ZapSwapCurve";
import { Zero, _ETH_CONSTANT } from "./helpers/constants";
import { setBlock } from "./helpers/forking";
import manipulateTokenBalance, {
  ContractLanguage,
} from "./helpers/manipulateTokenBalances";
import { calcBigNumberPercentage } from "./helpers/math";
import { getPermitSignature } from "./helpers/signatures";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { ONE_HOUR_IN_SECONDS } from "./helpers/time";

const { provider } = waffle;

const ZAP_BLOCK = 13583600;

const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const _3CRV = "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490";
const _3CRV_POOL = "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7";

const LUSD = "0x5f98805A4E8be255a32880FDeC7F6728C6568bA0";
const LUSD3CRV = "0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA";
const LUSD3CRV_POOL = "0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA";
const EP_CURVELUSD = "0xa2b3d083AA1eaa8453BfB477f062A208Ed85cBBF";

const STETH = "0xae7ab96520de3a18e5e111b5eaab095312d7fe84";
const STCRV = "0x06325440D014e39736583c165C2963BA99fAf14E";
const STCRV_POOL = "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022";
const EP_CRVSTETH = "0x2361102893CCabFb543bc55AC4cC8d6d0824A67E";

const WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";
const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const CRVTRICRYPTO = "0xc4AD29ba4B3c580e6D59105FFf484999997675Ff";
const CRVTRICRYPTO_POOL = "0xD51a44d3FaE010294C616388b506AcdA1bfAAE46";
const CRVTRICRYPTO_POOL_WRAPPER = "0x3993d34e7e99Abf6B6f367309975d1360222D446";
const EP_CRV3CRYPTO = "0x285328906D0D33cb757c1E471F5e2176683247c2";

export async function deploy(user: { user: Signer; address: string }) {
  const [authSigner] = await ethers.getSigners();

  const balancerVault = Vault__factory.connect(
    "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    user.user
  );

  const deployer = new ZapSwapCurve__factory(authSigner);
  const zapSwapCurve = await deployer.deploy(balancerVault.address);

  await zapSwapCurve.connect(authSigner).authorize(authSigner.address);
  await zapSwapCurve.connect(authSigner).setOwner(authSigner.address);

  const tokensAndSpenders: { token: string; spender: string }[] = [
    { token: DAI, spender: _3CRV_POOL },
    { token: USDC, spender: _3CRV_POOL },
    { token: USDT, spender: _3CRV_POOL },
    { token: DAI, spender: zapSwapCurve.address },
    { token: USDC, spender: zapSwapCurve.address },
    { token: USDT, spender: zapSwapCurve.address },

    { token: _3CRV, spender: LUSD3CRV_POOL },
    { token: LUSD, spender: LUSD3CRV_POOL },
    { token: _3CRV, spender: zapSwapCurve.address },
    { token: LUSD, spender: zapSwapCurve.address },
    { token: LUSD3CRV, spender: balancerVault.address },
    { token: EP_CURVELUSD, spender: balancerVault.address },

    { token: STETH, spender: zapSwapCurve.address },
    { token: STETH, spender: STCRV_POOL },
    { token: STCRV, spender: STCRV_POOL },
    { token: STCRV, spender: balancerVault.address },
    { token: EP_CRVSTETH, spender: balancerVault.address },

    { token: WBTC, spender: CRVTRICRYPTO_POOL },
    { token: WBTC, spender: CRVTRICRYPTO_POOL_WRAPPER },
    { token: WBTC, spender: zapSwapCurve.address },
    { token: USDT, spender: CRVTRICRYPTO_POOL },
    { token: USDT, spender: CRVTRICRYPTO_POOL_WRAPPER },
    { token: WETH, spender: CRVTRICRYPTO_POOL },
    { token: WETH, spender: zapSwapCurve.address },
    { token: CRVTRICRYPTO, spender: CRVTRICRYPTO_POOL_WRAPPER },
    { token: CRVTRICRYPTO, spender: balancerVault.address },
    { token: EP_CRV3CRYPTO, spender: balancerVault.address },
  ];

  const tokens = tokensAndSpenders.map(({ token }) => token);
  const spenders = tokensAndSpenders.map(({ spender }) => spender);
  await zapSwapCurve.setApprovalsFor(
    tokens,
    spenders,
    spenders.map(() => ethers.constants.MaxUint256)
  );

  await Promise.all(
    [
      DAI,
      USDC,
      USDT,
      _3CRV,
      LUSD,
      EP_CURVELUSD,
      STETH,
      EP_CRVSTETH,
      WBTC,
      WETH,
      EP_CRV3CRYPTO,
    ].map((token) =>
      ERC20__factory.connect(token, user.user).approve(
        zapSwapCurve.address,
        ethers.constants.MaxUint256
      )
    )
  );
  return { zapSwapCurve };
}

const SLIPPAGE = 2; // 2%
const DEADLINE = Math.round(Date.now() / 1000) + ONE_HOUR_IN_SECONDS;

const emptyZapCurveIn: ZapCurveLpInStruct = {
  curvePool: ethers.constants.AddressZero,
  lpToken: ethers.constants.AddressZero,
  amounts: [Zero, Zero],
  roots: [ethers.constants.AddressZero, ethers.constants.AddressZero],
  parentIdx: Zero,
  minLpAmount: Zero,
};

const emptyZapCurveOut: ZapCurveLpOutStruct = {
  curvePool: ethers.constants.AddressZero,
  lpToken: ethers.constants.AddressZero,
  rootTokenIdx: Zero,
  curveRemoveLiqFnIsUint256: false,
  rootToken: ethers.constants.AddressZero,
};

describe("ZapSwapCurve", () => {
  let users: { user: Signer; address: string }[];
  let initBlock: number;
  let zapSwapCurve: ZapSwapCurve;

  before(async () => {
    initBlock = await provider.getBlockNumber();
    await createSnapshot(provider);
    // Do not change block as dependencies might change
    await setBlock(ZAP_BLOCK);

    users = ((await ethers.getSigners()) as Signer[]).map((user) => ({
      user,
      address: "",
    }));

    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    ({ zapSwapCurve } = await deploy(users[1]));
  });

  after(async () => {
    await restoreSnapshot(provider);
    setBlock(initBlock);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("ETH:STETH <-> ePyvcrvSTETH", () => {
    const zapInInfo: ZapInInfoStruct = {
      balancerPoolId:
        "0xb03c6b351a283bc1cd26b9cf6d7b0c4556013bdb0002000000000000000000ab",
      recipient: ethers.constants.AddressZero,
      principalToken: EP_CRVSTETH,
      minPtAmount: Zero,
      deadline: DEADLINE,
      needsChildZap: false,
    };

    const zapCurveIn: ZapCurveLpInStruct = {
      curvePool: STCRV_POOL,
      lpToken: STCRV,
      amounts: [Zero, Zero],
      roots: [_ETH_CONSTANT, STETH],
      parentIdx: Zero,
      minLpAmount: Zero,
    };

    const zapOutInfo: ZapOutInfoStruct = {
      balancerPoolId: zapInInfo.balancerPoolId,
      principalToken: EP_CRVSTETH,
      principalTokenAmount: Zero,
      minBaseTokenAmount: Zero,
      minRootTokenAmount: Zero,
      deadline: DEADLINE,
      recipient: ethers.constants.AddressZero,
      targetNeedsChildZap: false,
    };

    const zapCurveOut: ZapCurveLpOutStruct = {
      ...emptyZapCurveOut,
      curvePool: STCRV_POOL,
      lpToken: STCRV,
    };

    it("should swap ETH for ePyvcrvSTETH", async () => {
      const inputAmount = ethers.utils.parseEther("10");
      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        { ...zapCurveIn, amounts: [inputAmount, Zero] },
        emptyZapCurveIn,
        [],
        { value: inputAmount }
      );

      const outputAmount = await ERC20__factory.connect(
        EP_CRVSTETH,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvcrvSTETH to ETH", async () => {
      const inputAmount = ethers.utils.parseEther("10");
      const recipient = users[2].address;
      const userPreBalance = await provider.getBalance(recipient);

      await manipulateTokenBalance(
        EP_CRVSTETH,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapOut(
        {
          ...zapOutInfo,
          principalTokenAmount: inputAmount,
          minRootTokenAmount: minOutputAmount,
          recipient,
        },
        {
          ...zapCurveOut,
          rootTokenIdx: 0,
          rootToken: _ETH_CONSTANT,
        },
        emptyZapCurveOut,
        []
      );

      const userPostBalance = await provider.getBalance(recipient);
      const outputAmount = userPostBalance.sub(userPreBalance);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap stETH for ePyvcrvSTETH", async () => {
      const inputAmount = ethers.utils.parseEther("100");
      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await manipulateTokenBalance(
        STETH,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        { ...zapCurveIn, amounts: [Zero, inputAmount] },
        emptyZapCurveIn,
        []
      );

      const outputAmount = await ERC20__factory.connect(
        EP_CRVSTETH,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvcrvSTETH to stETH", async () => {
      const inputAmount = ethers.utils.parseEther("100");

      await manipulateTokenBalance(
        EP_CRVSTETH,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapOut(
        {
          ...zapOutInfo,
          principalTokenAmount: inputAmount,
          minRootTokenAmount: minOutputAmount,
          recipient: users[1].address,
        },
        {
          ...zapCurveOut,
          rootTokenIdx: 1,
          rootToken: STETH,
        },
        emptyZapCurveOut,
        []
      );

      const outputAmount = await ERC20__factory.connect(
        STETH,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap stETH & ETH for ePyvcrvSTETH", async () => {
      const inputAmount = ethers.utils.parseEther("100");
      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await ERC20__factory.connect(STETH, users[1].user).approve(
        zapSwapCurve.address,
        ethers.constants.MaxUint256
      );

      await manipulateTokenBalance(
        STETH,
        ContractLanguage.Solidity,
        inputAmount.div(2),
        users[1].address
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        { ...zapCurveIn, amounts: [inputAmount.div(2), inputAmount.div(2)] },
        emptyZapCurveIn,
        [],
        { value: inputAmount.div(2) }
      );

      const outputAmount = await ERC20__factory.connect(
        EP_CRVSTETH,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });
  });

  describe("USDT:WBTC:WETH <-> ePyvcrv3crypto", () => {
    const zapInInfo: ZapInInfoStruct = {
      balancerPoolId:
        "0x6dd0f7c8f4793ed2531c0df4fea8633a21fdcff40002000000000000000000b7",
      recipient: ethers.constants.AddressZero,
      principalToken: EP_CRV3CRYPTO,
      minPtAmount: Zero,
      deadline: DEADLINE,
      needsChildZap: false,
    };

    const zapCurveIn: ZapCurveLpInStruct = {
      curvePool: CRVTRICRYPTO_POOL,
      lpToken: CRVTRICRYPTO,
      amounts: [Zero, Zero],
      roots: [USDT, WBTC, WETH],
      parentIdx: Zero,
      minLpAmount: Zero,
    };

    const zapOutInfo: ZapOutInfoStruct = {
      balancerPoolId: zapInInfo.balancerPoolId,
      principalToken: EP_CRV3CRYPTO,
      principalTokenAmount: Zero,
      minBaseTokenAmount: Zero,
      minRootTokenAmount: Zero,
      deadline: DEADLINE,
      recipient: ethers.constants.AddressZero,
      targetNeedsChildZap: false,
    };

    const zapCurveOut: ZapCurveLpOutStruct = {
      ...emptyZapCurveOut,
      curveRemoveLiqFnIsUint256: true,
      curvePool: CRVTRICRYPTO_POOL,
      lpToken: CRVTRICRYPTO,
    };

    it("should swap USDT for ePyvcrv3crypto", async () => {
      const inputAmount = ethers.utils.parseUnits("5000", 6);

      await manipulateTokenBalance(
        USDT,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const expectedPtAmount = await zapSwapCurve
        .connect(users[1].user)
        .callStatic.zapIn(
          {
            ...zapInInfo,
            recipient: users[1].address,
            minPtAmount: 0,
          },
          { ...zapCurveIn, amounts: [inputAmount, Zero, Zero] },
          emptyZapCurveIn,
          []
        );

      const minOutputAmount = expectedPtAmount.sub(
        calcBigNumberPercentage(expectedPtAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        { ...zapCurveIn, amounts: [inputAmount, Zero, Zero] },
        emptyZapCurveIn,
        []
      );

      const outputAmount = await ERC20__factory.connect(
        EP_CRV3CRYPTO,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvcrv3crypto to USDT", async () => {
      const inputAmount = ethers.utils.parseEther("10");

      await manipulateTokenBalance(
        EP_CRV3CRYPTO,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const info = {
        ...zapOutInfo,
        principalTokenAmount: inputAmount,
        minRootTokenAmount: 0,
        recipient: users[1].address,
      };

      const zap = {
        ...zapCurveOut,
        rootTokenIdx: 0,
        rootToken: USDT,
      };

      const expectedPtAmount = await zapSwapCurve
        .connect(users[1].user)
        .callStatic.zapOut(info, zap, emptyZapCurveOut, []);

      const minOutputAmount = expectedPtAmount.sub(
        calcBigNumberPercentage(expectedPtAmount, SLIPPAGE)
      );

      await zapSwapCurve
        .connect(users[1].user)
        .zapOut(
          { ...info, minRootTokenAmount: minOutputAmount },
          zap,
          emptyZapCurveOut,
          []
        );

      const outputAmount = await ERC20__factory.connect(
        USDT,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap WBTC for ePyvcrv3crypto", async () => {
      const inputAmount = ethers.utils.parseUnits("0.2", 8);

      await manipulateTokenBalance(
        WBTC,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const info = {
        ...zapInInfo,
        recipient: users[1].address,
        minPtAmount: 0,
      };

      const zap = { ...zapCurveIn, amounts: [Zero, inputAmount, Zero] };

      const expectedPtAmount = await zapSwapCurve
        .connect(users[1].user)
        .callStatic.zapIn(info, zap, emptyZapCurveIn, []);

      const minOutputAmount = expectedPtAmount.sub(
        calcBigNumberPercentage(expectedPtAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...info,
          minPtAmount: minOutputAmount,
        },
        zap,
        emptyZapCurveIn,
        []
      );

      const outputAmount = await ERC20__factory.connect(
        EP_CRV3CRYPTO,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvcrv3crypto to WBTC", async () => {
      const inputAmount = ethers.utils.parseEther("10");

      await manipulateTokenBalance(
        EP_CRV3CRYPTO,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const info = {
        ...zapOutInfo,
        principalTokenAmount: inputAmount,
        minRootTokenAmount: 0,
        recipient: users[1].address,
      };

      const zap = {
        ...zapCurveOut,
        rootTokenIdx: 1,
        rootToken: WBTC,
      };

      const expectedPtAmount = await zapSwapCurve
        .connect(users[1].user)
        .callStatic.zapOut(info, zap, emptyZapCurveOut, []);

      const minOutputAmount = expectedPtAmount.sub(
        calcBigNumberPercentage(expectedPtAmount, SLIPPAGE)
      );

      await zapSwapCurve
        .connect(users[1].user)
        .zapOut(
          { ...info, minRootTokenAmount: minOutputAmount },
          zap,
          emptyZapCurveOut,
          []
        );

      const outputAmount = await ERC20__factory.connect(
        WBTC,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap WETH for ePyvcrv3crypto", async () => {
      const inputAmount = ethers.utils.parseEther("2");

      await manipulateTokenBalance(
        WETH,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const info = {
        ...zapInInfo,
        recipient: users[1].address,
        minPtAmount: 0,
      };

      const zap = { ...zapCurveIn, amounts: [Zero, Zero, inputAmount] };

      const expectedPtAmount = await zapSwapCurve
        .connect(users[1].user)
        .callStatic.zapIn(info, zap, emptyZapCurveIn, []);

      const minOutputAmount = expectedPtAmount.sub(
        calcBigNumberPercentage(expectedPtAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...info,
          minPtAmount: minOutputAmount,
        },
        zap,
        emptyZapCurveIn,
        []
      );

      const outputAmount = await ERC20__factory.connect(
        EP_CRV3CRYPTO,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvcrv3crypto to WETH", async () => {
      const inputAmount = ethers.utils.parseEther("10");

      await manipulateTokenBalance(
        EP_CRV3CRYPTO,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const info = {
        ...zapOutInfo,
        principalTokenAmount: inputAmount,
        minRootTokenAmount: 0,
        recipient: users[1].address,
      };

      const zap = {
        ...zapCurveOut,
        rootTokenIdx: 2,
        rootToken: WETH,
      };

      const expectedPtAmount = await zapSwapCurve
        .connect(users[1].user)
        .callStatic.zapOut(info, zap, emptyZapCurveOut, []);

      const minOutputAmount = expectedPtAmount.sub(
        calcBigNumberPercentage(expectedPtAmount, SLIPPAGE)
      );

      await zapSwapCurve
        .connect(users[1].user)
        .zapOut(
          { ...info, minRootTokenAmount: minOutputAmount },
          zap,
          emptyZapCurveOut,
          []
        );

      const outputAmount = await ERC20__factory.connect(
        WETH,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ETH as WETH for ePyvcrv3crypto", async () => {
      const inputAmount = ethers.utils.parseEther("2");

      const info = {
        ...zapInInfo,
        recipient: users[1].address,
        minPtAmount: 0,
      };

      const zap = {
        ...zapCurveIn,
        curvePool: CRVTRICRYPTO_POOL_WRAPPER,
        roots: [zapCurveIn.roots[0], zapCurveIn.roots[1], _ETH_CONSTANT],
        amounts: [Zero, Zero, inputAmount],
      };

      const expectedPtAmount = await zapSwapCurve
        .connect(users[1].user)
        .callStatic.zapIn(info, zap, emptyZapCurveIn, [], {
          value: inputAmount,
        });

      const minOutputAmount = expectedPtAmount.sub(
        calcBigNumberPercentage(expectedPtAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...info,
          minPtAmount: minOutputAmount,
        },
        zap,
        emptyZapCurveIn,
        [],
        { value: inputAmount }
      );

      const outputAmount = await ERC20__factory.connect(
        EP_CRV3CRYPTO,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvcrv3crypto for WETH than to ETH", async () => {
      const inputAmount = ethers.utils.parseEther("10");

      const recipient = users[2].address;
      const userPreBalance = await provider.getBalance(recipient);

      await manipulateTokenBalance(
        EP_CRV3CRYPTO,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const info = {
        ...zapOutInfo,
        principalTokenAmount: inputAmount,
        minRootTokenAmount: 0,
        recipient,
      };

      const zap = {
        ...zapCurveOut,
        curvePool: CRVTRICRYPTO_POOL_WRAPPER,
        rootTokenIdx: 2,
        rootToken: _ETH_CONSTANT,
      };

      const expectedPtAmount = await zapSwapCurve
        .connect(users[1].user)
        .callStatic.zapOut(info, zap, emptyZapCurveOut, []);

      const minOutputAmount = expectedPtAmount.sub(
        calcBigNumberPercentage(expectedPtAmount, SLIPPAGE)
      );

      await zapSwapCurve
        .connect(users[1].user)
        .zapOut(
          { ...info, minRootTokenAmount: minOutputAmount },
          zap,
          emptyZapCurveOut,
          []
        );

      const userPostBalance = await provider.getBalance(recipient);
      const outputAmount = userPostBalance.sub(userPreBalance);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap WBTC,USDT & ETH for ePyvcrv3crypto", async () => {
      const info = {
        ...zapInInfo,
        recipient: users[1].address,
        minPtAmount: 0,
      };
      await manipulateTokenBalance(
        WBTC,
        ContractLanguage.Solidity,
        ethers.utils.parseUnits("0.2", 8),
        users[1].address
      );
      await manipulateTokenBalance(
        USDT,
        ContractLanguage.Solidity,
        ethers.utils.parseUnits("5000", 6),
        users[1].address
      );

      const zap = {
        ...zapCurveIn,
        curvePool: CRVTRICRYPTO_POOL_WRAPPER,
        roots: [zapCurveIn.roots[0], zapCurveIn.roots[1], _ETH_CONSTANT],
        amounts: [
          ethers.utils.parseUnits("5000", 6),
          ethers.utils.parseUnits("0.2", 8),
          ethers.utils.parseEther("2"),
        ],
      };

      const expectedPtAmount = await zapSwapCurve
        .connect(users[1].user)
        .callStatic.zapIn(info, zap, emptyZapCurveIn, [], {
          value: ethers.utils.parseEther("2"),
        });

      const minOutputAmount = expectedPtAmount.sub(
        calcBigNumberPercentage(expectedPtAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...info,
          minPtAmount: minOutputAmount,
        },
        zap,
        emptyZapCurveIn,
        [],
        { value: ethers.utils.parseEther("2") }
      );

      const outputAmount = await ERC20__factory.connect(
        EP_CRV3CRYPTO,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });
  });

  describe("LUSD:3Crv:DAI:USDC:USDT <-> ePyvCurveLUSD", () => {
    const zapInInfo: ZapInInfoStruct = {
      balancerPoolId:
        "0x893b30574bf183d69413717f30b17062ec9dfd8b000200000000000000000061",
      recipient: ethers.constants.AddressZero,
      principalToken: EP_CURVELUSD,
      minPtAmount: Zero,
      deadline: DEADLINE,
      needsChildZap: true,
    };

    const zapCurveIn: ZapCurveLpInStruct = {
      curvePool: LUSD3CRV_POOL,
      lpToken: LUSD3CRV,
      amounts: [Zero, Zero],
      roots: [LUSD, _3CRV],
      parentIdx: Zero,
      minLpAmount: Zero,
    };

    const childZapCurveIn: ZapCurveLpInStruct = {
      curvePool: _3CRV_POOL,
      lpToken: _3CRV,
      amounts: [Zero, Zero, Zero],
      roots: [DAI, USDC, USDT],
      parentIdx: 1,
      minLpAmount: Zero,
    };

    const zapOutInfo: ZapOutInfoStruct = {
      balancerPoolId: zapInInfo.balancerPoolId,
      principalToken: EP_CURVELUSD,
      principalTokenAmount: Zero,
      minBaseTokenAmount: Zero,
      minRootTokenAmount: Zero,
      deadline: DEADLINE,
      recipient: ethers.constants.AddressZero,
      targetNeedsChildZap: true,
    };

    const zapCurveOut: ZapCurveLpOutStruct = {
      ...emptyZapCurveOut,
      curvePool: LUSD3CRV_POOL,
      lpToken: LUSD3CRV,
    };

    const childZapCurveOut: ZapCurveLpOutStruct = {
      ...emptyZapCurveOut,
      curvePool: _3CRV_POOL,
      lpToken: _3CRV,
    };

    it("should swap DAI for ePyvCurveLUSD", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await manipulateTokenBalance(
        DAI,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        zapCurveIn,
        { ...childZapCurveIn, amounts: [inputAmount, Zero, Zero] },
        []
      );
      const outputAmount = await ERC20__factory.connect(
        EP_CURVELUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvCurveLUSD to DAI", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await manipulateTokenBalance(
        EP_CURVELUSD,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapOut(
        {
          ...zapOutInfo,
          recipient: users[1].address,
          minRootTokenAmount: minOutputAmount,
          principalTokenAmount: inputAmount,
        },
        { ...zapCurveOut, rootToken: _3CRV, rootTokenIdx: 1 },
        { ...childZapCurveOut, rootToken: DAI, rootTokenIdx: 0 },
        []
      );

      const outputAmount = await ERC20__factory.connect(
        DAI,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap USDC for ePyvCurveLUSD", async () => {
      const inputAmount = ethers.utils.parseUnits("5000", 6);

      await manipulateTokenBalance(
        USDC,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        zapCurveIn,
        { ...childZapCurveIn, amounts: [Zero, inputAmount, Zero] },
        []
      );
      const outputAmount = await ERC20__factory.connect(
        EP_CURVELUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvCurveLUSD to USDC", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await manipulateTokenBalance(
        EP_CURVELUSD,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const adjustedInputAmount = ethers.utils.parseUnits(
        ethers.utils.formatEther(inputAmount),
        6
      );
      const minOutputAmount = adjustedInputAmount.sub(
        calcBigNumberPercentage(adjustedInputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapOut(
        {
          ...zapOutInfo,
          recipient: users[1].address,
          minRootTokenAmount: minOutputAmount,
          principalTokenAmount: inputAmount,
        },
        { ...zapCurveOut, rootToken: _3CRV, rootTokenIdx: 1 },
        { ...childZapCurveOut, rootToken: USDC, rootTokenIdx: 1 },
        []
      );

      const outputAmount = await ERC20__factory.connect(
        USDC,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap USDT for ePyvCurveLUSD", async () => {
      const inputAmount = ethers.utils.parseUnits("5000", 6);

      await manipulateTokenBalance(
        USDT,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        zapCurveIn,
        { ...childZapCurveIn, amounts: [Zero, Zero, inputAmount] },
        []
      );
      const outputAmount = await ERC20__factory.connect(
        EP_CURVELUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvCurveLUSD to USDT", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await manipulateTokenBalance(
        EP_CURVELUSD,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );
      const adjustedInputAmount = ethers.utils.parseUnits(
        ethers.utils.formatEther(inputAmount),
        6
      );
      const minOutputAmount = adjustedInputAmount.sub(
        calcBigNumberPercentage(adjustedInputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapOut(
        {
          ...zapOutInfo,
          recipient: users[1].address,
          minRootTokenAmount: minOutputAmount,
          principalTokenAmount: inputAmount,
        },
        { ...zapCurveOut, rootToken: _3CRV, rootTokenIdx: 1 },
        { ...childZapCurveOut, rootToken: USDT, rootTokenIdx: 2 },
        []
      );

      const outputAmount = await ERC20__factory.connect(
        USDT,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap LUSD for ePyvCurveLUSD", async () => {
      const inputAmount = ethers.utils.parseUnits("5000", 6);

      await manipulateTokenBalance(
        LUSD,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
          needsChildZap: false,
        },
        { ...zapCurveIn, amounts: [inputAmount, Zero] },
        emptyZapCurveIn,
        []
      );
      const outputAmount = await ERC20__factory.connect(
        EP_CURVELUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should permit and swap LUSD to ePyvCurveLUSD", async () => {
      const inputAmount = ethers.utils.parseUnits("5000", 6);

      await manipulateTokenBalance(
        LUSD,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );
      await (
        await ERC20__factory.connect(LUSD, users[1].user).approve(
          zapSwapCurve.address,
          Zero
        )
      ).wait(1);
      const { v, r, s } = await getPermitSignature(
        ERC20Permit__factory.connect(LUSD, users[1].user),
        users[1].address,
        zapSwapCurve.address,
        ethers.constants.MaxUint256,
        "1"
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
          needsChildZap: false,
        },
        { ...zapCurveIn, amounts: [inputAmount, Zero] },
        emptyZapCurveIn,
        [
          {
            v,
            r,
            s,
            tokenContract: LUSD,
            spender: zapSwapCurve.address,
            expiration: ethers.constants.MaxUint256,
            amount: ethers.constants.MaxUint256,
          },
        ]
      );

      const outputAmount = await ERC20__factory.connect(
        EP_CURVELUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvCurveLUSD to LUSD", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await manipulateTokenBalance(
        EP_CURVELUSD,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapOut(
        {
          ...zapOutInfo,
          recipient: users[1].address,
          minRootTokenAmount: minOutputAmount,
          principalTokenAmount: inputAmount,
          targetNeedsChildZap: false,
        },
        { ...zapCurveOut, rootToken: LUSD, rootTokenIdx: 0 },
        emptyZapCurveOut,
        []
      );

      const outputAmount = await ERC20__factory.connect(
        LUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should permit & swap ePyvCurveLUSD to LUSD", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await manipulateTokenBalance(
        EP_CURVELUSD,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      await (
        await ERC20__factory.connect(EP_CURVELUSD, users[1].user).approve(
          zapSwapCurve.address,
          Zero
        )
      ).wait(1);
      const { v, r, s } = await getPermitSignature(
        ERC20Permit__factory.connect(EP_CURVELUSD, users[1].user),
        users[1].address,
        zapSwapCurve.address,
        ethers.constants.MaxUint256,
        "1",
        1
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapOut(
        {
          ...zapOutInfo,
          recipient: users[1].address,
          minRootTokenAmount: minOutputAmount,
          principalTokenAmount: inputAmount,
          targetNeedsChildZap: false,
        },
        { ...zapCurveOut, rootToken: LUSD, rootTokenIdx: 0 },
        emptyZapCurveOut,
        [
          {
            v,
            r,
            s,
            tokenContract: EP_CURVELUSD,
            spender: zapSwapCurve.address,
            expiration: ethers.constants.MaxUint256,
            amount: ethers.constants.MaxUint256,
          },
        ]
      );

      const outputAmount = await ERC20__factory.connect(
        LUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap 3Crv for ePyvCurveLUSD", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await manipulateTokenBalance(
        _3CRV,
        ContractLanguage.Vyper,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
          needsChildZap: false,
        },
        { ...zapCurveIn, amounts: [Zero, inputAmount] },
        emptyZapCurveIn,
        []
      );
      const outputAmount = await ERC20__factory.connect(
        EP_CURVELUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap ePyvCurveLUSD to 3Crv", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await manipulateTokenBalance(
        EP_CURVELUSD,
        ContractLanguage.Solidity,
        inputAmount,
        users[1].address
      );

      const minOutputAmount = inputAmount.sub(
        calcBigNumberPercentage(inputAmount, SLIPPAGE)
      );

      await zapSwapCurve.connect(users[1].user).zapOut(
        {
          ...zapOutInfo,
          recipient: users[1].address,
          minRootTokenAmount: minOutputAmount,
          principalTokenAmount: inputAmount,
          targetNeedsChildZap: false,
        },
        { ...zapCurveOut, rootToken: _3CRV, rootTokenIdx: 1 },
        emptyZapCurveOut,
        []
      );

      const outputAmount = await ERC20__factory.connect(
        _3CRV,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap LUSD and DAI for ePyvCurveLUSD", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await Promise.all(
        [DAI, LUSD].map((token) =>
          manipulateTokenBalance(
            token,
            ContractLanguage.Solidity,
            inputAmount,
            users[1].address
          )
        )
      );

      const minOutputAmount = inputAmount
        .mul(2)
        .sub(calcBigNumberPercentage(inputAmount.mul(2), SLIPPAGE));

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        { ...zapCurveIn, amounts: [inputAmount, Zero] },
        { ...childZapCurveIn, amounts: [inputAmount, Zero, Zero] },
        []
      );
      const outputAmount = await ERC20__factory.connect(
        EP_CURVELUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap 3Crv and DAI for ePyvCurveLUSD", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await Promise.all(
        [DAI, _3CRV].map((token) =>
          manipulateTokenBalance(
            token,
            token !== _3CRV
              ? ContractLanguage.Solidity
              : ContractLanguage.Vyper,
            inputAmount,
            users[1].address
          )
        )
      );

      const minOutputAmount = inputAmount
        .mul(2)
        .sub(calcBigNumberPercentage(inputAmount.mul(2), SLIPPAGE));

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        { ...zapCurveIn, amounts: [Zero, inputAmount] },
        { ...childZapCurveIn, amounts: [inputAmount, Zero, Zero] },
        []
      );
      const outputAmount = await ERC20__factory.connect(
        EP_CURVELUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });

    it("should swap LUSD, DAI, USDC, USDT & ThreeCrv for ePyvCurveLUSD", async () => {
      const inputAmount = ethers.utils.parseEther("5000");

      await Promise.all(
        [DAI, _3CRV, LUSD].map((token) =>
          manipulateTokenBalance(
            token,
            token !== _3CRV
              ? ContractLanguage.Solidity
              : ContractLanguage.Vyper,
            inputAmount,
            users[1].address
          )
        )
      );

      await manipulateTokenBalance(
        USDT,
        ContractLanguage.Solidity,
        ethers.utils.parseUnits("5000", 6),
        users[1].address
      );

      await manipulateTokenBalance(
        USDC,
        ContractLanguage.Solidity,
        ethers.utils.parseUnits("5000", 6),
        users[1].address
      );

      const minOutputAmount = inputAmount
        .mul(5)
        .sub(calcBigNumberPercentage(inputAmount.mul(5), SLIPPAGE));

      await zapSwapCurve.connect(users[1].user).zapIn(
        {
          ...zapInInfo,
          recipient: users[1].address,
          minPtAmount: minOutputAmount,
        },
        { ...zapCurveIn, amounts: [inputAmount, inputAmount] },
        {
          ...childZapCurveIn,
          amounts: [
            inputAmount,
            ethers.utils.parseUnits("5000", 6),
            ethers.utils.parseUnits("5000", 6),
          ],
        },
        []
      );
      const outputAmount = await ERC20__factory.connect(
        EP_CURVELUSD,
        users[1].user
      ).balanceOf(users[1].address);

      expect(outputAmount.gte(minOutputAmount)).to.be.true;
    });
  });
});
