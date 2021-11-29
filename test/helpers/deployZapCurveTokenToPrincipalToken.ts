import { BigNumber, Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { ZapCurveTokenToPrincipalToken__factory } from "typechain/factories/ZapCurveTokenToPrincipalToken__factory";
import { ConvergentCurvePool__factory } from "typechain/factories/ConvergentCurvePool__factory";
import { IERC20__factory } from "typechain/factories/IERC20__factory";
import { Tranche__factory } from "typechain/factories/Tranche__factory";
import { Vault__factory } from "typechain/factories/Vault__factory";
import { IERC20 } from "typechain/IERC20";
import { Tranche } from "typechain/Tranche";
import { Vault } from "typechain/Vault";
import {
  ZapCurveTokenToPrincipalToken,
  ZapCurveLpInStruct,
  ZapOutInfoStruct,
  ZapInInfoStruct,
  ZapCurveLpOutStruct,
} from "typechain/ZapCurveTokenToPrincipalToken";
import { ZERO, _ETH_CONSTANT } from "./constants";
import { impersonate, stopImpersonating } from "./impersonate";
import { calcBigNumberPercentage } from "./math";
import { ONE_DAY_IN_SECONDS } from "./time";

const { provider } = waffle;

export interface PrincipalTokenCurveTrie {
  name: string;
  token: Tranche;
  slippagePercentage: number;
  balancerPoolId: string;
  baseToken: BaseTokenTrie;
}

type BaseTokenTrie = {
  name: string;
  pool: string;
  token: IERC20;
} & (
  | TwoRootTokens<RootTokenKind.Basic | RootTokenKind.LpToken>
  | ThreeRootTokens<RootTokenKind.Basic | RootTokenKind.LpToken>
);

enum RootTokenKind {
  Basic = "Basic",
  LpToken = "LpToken",
}

interface TwoRootTokens<K extends RootTokenKind> {
  numberOfRoots: 2;
  roots: [RootToken<K>, RootToken<K>];
}

interface ThreeRootTokens<K extends RootTokenKind> {
  numberOfRoots: 3;
  roots: [RootToken<K>, RootToken<K>, RootToken<K>];
}

type RootToken<K extends RootTokenKind> = {
  name: string;
  token: IERC20 | { address: string };
  whale?: string;
} & (K extends RootTokenKind.Basic
  ? { kind: RootTokenKind.Basic }
  : { kind: RootTokenKind.LpToken; pool: string } & (
      | TwoRootTokens<RootTokenKind.Basic>
      | ThreeRootTokens<RootTokenKind.Basic>
    ));

export async function deploy(user: { user: Signer; address: string }): Promise<{
  zapCurveTokenToPrincipalToken: ZapCurveTokenToPrincipalToken;
  balancerVault: Vault;
  ePyvcrvSTETH: PrincipalTokenCurveTrie;
  ePyvcrv3crypto: PrincipalTokenCurveTrie;
  ePyvCurveLUSD: PrincipalTokenCurveTrie;
}> {
  const [authSigner] = await ethers.getSigners();

  const balancerVault = Vault__factory.connect(
    "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    user.user
  );

  const deployer = new ZapCurveTokenToPrincipalToken__factory(authSigner);
  const zapCurveTokenToPrincipalToken = await deployer.deploy(
    balancerVault.address
  );

  await zapCurveTokenToPrincipalToken
    .connect(authSigner)
    .authorize(authSigner.address);
  await zapCurveTokenToPrincipalToken
    .connect(authSigner)
    .setOwner(authSigner.address);

  const ePyvcrvSTETH: PrincipalTokenCurveTrie = {
    name: "ePyvcrvSTETH",
    token: Tranche__factory.connect(
      "0x2361102893CCabFb543bc55AC4cC8d6d0824A67E",
      user.user
    ),
    slippagePercentage: 0.2,
    balancerPoolId:
      "0xb03c6b351a283bc1cd26b9cf6d7b0c4556013bdb0002000000000000000000ab",
    baseToken: {
      name: "stCRV",
      token: IERC20__factory.connect(
        "0x06325440D014e39736583c165C2963BA99fAf14E",
        user.user
      ),
      pool: "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022",
      numberOfRoots: 2,
      roots: [
        {
          kind: RootTokenKind.Basic,
          name: "ETH",
          token: { address: _ETH_CONSTANT },
        },
        {
          kind: RootTokenKind.Basic,
          name: "stETH",
          token: IERC20__factory.connect(
            "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",
            user.user
          ),
          whale: "0x06920C9fC643De77B99cB7670A944AD31eaAA260",
        },
      ],
    },
  };

  const ePyvcrv3crypto: PrincipalTokenCurveTrie = {
    name: "ePyvcrv3crypto",
    token: Tranche__factory.connect(
      "0x285328906D0D33cb757c1E471F5e2176683247c2",
      user.user
    ),
    slippagePercentage: 1,
    balancerPoolId:
      "0x6dd0f7c8f4793ed2531c0df4fea8633a21fdcff40002000000000000000000b7",
    baseToken: {
      name: "crvTriCrypto",
      token: IERC20__factory.connect(
        "0xc4AD29ba4B3c580e6D59105FFf484999997675Ff",
        user.user
      ),
      pool: "0xD51a44d3FaE010294C616388b506AcdA1bfAAE46",
      numberOfRoots: 3,
      roots: [
        {
          kind: RootTokenKind.Basic,
          name: "USDT",
          token: IERC20__factory.connect(
            "0xdac17f958d2ee523a2206206994597c13d831ec7",
            user.user
          ),
          whale: "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
        },
        {
          kind: RootTokenKind.Basic,
          name: "WBTC",
          token: IERC20__factory.connect(
            "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
            user.user
          ),
          whale: "0xE3DD3914aB28bB552d41B8dFE607355DE4c37A51",
        },
        {
          kind: RootTokenKind.Basic,
          name: "WETH",
          token: IERC20__factory.connect(
            "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
            user.user
          ),
          whale: "0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3",
        },
      ],
    },
  };

  const ePyvCurveLUSD: PrincipalTokenCurveTrie = {
    name: "ePyvCurveLUSD",
    token: Tranche__factory.connect(
      "0xa2b3d083AA1eaa8453BfB477f062A208Ed85cBBF",
      user.user
    ),
    slippagePercentage: 0.075,
    balancerPoolId:
      "0x893b30574bf183d69413717f30b17062ec9dfd8b000200000000000000000061",
    baseToken: {
      name: "LUSD3CRV_F",
      token: IERC20__factory.connect(
        "0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA",
        user.user
      ),
      pool: "0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA",
      numberOfRoots: 2,
      roots: [
        {
          kind: RootTokenKind.Basic,
          name: "LUSD",
          token: IERC20__factory.connect(
            "0x5f98805A4E8be255a32880FDeC7F6728C6568bA0",
            user.user
          ),
          whale: "0xE05fD1304C1CfE19dcc6AAb0767848CC4A8f54aa",
        },
        {
          kind: RootTokenKind.LpToken,
          name: "3Crv",
          token: IERC20__factory.connect(
            "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490",
            user.user
          ),
          pool: "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
          whale: "0x0B096d1f0ba7Ef2b3C7ecB8d4a5848043CdeBD50",
          numberOfRoots: 3,
          roots: [
            {
              kind: RootTokenKind.Basic,
              name: "DAI",
              token: IERC20__factory.connect(
                "0x6B175474E89094C44Da98b954EedeAC495271d0F",
                user.user
              ),
              whale: "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
            },
            {
              kind: RootTokenKind.Basic,
              name: "USDC",
              token: IERC20__factory.connect(
                "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                user.user
              ),
              whale: "0xdb49552EeFB89416b9A412138c009a004f54BAd0",
            },
            {
              kind: RootTokenKind.Basic,
              name: "USDT",
              token: IERC20__factory.connect(
                "0xdac17f958d2ee523a2206206994597c13d831ec7",
                user.user
              ),
              whale: "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
            },
          ],
        },
      ],
    },
  };

  const { tokens: tokenAddresses, spenders } = [
    ePyvcrvSTETH,
    ePyvcrv3crypto,
    ePyvCurveLUSD,
  ].reduce(
    ({ tokens, spenders }, trie) => {
      const {
        token: { address: principalTokenAddress },
      } = trie;
      const {
        token: { address: baseTokenAddress },
        pool: baseTokenPool,
        roots: baseTokenRoots,
      } = trie.baseToken;
      tokens = [
        ...tokens,
        baseTokenAddress,
        principalTokenAddress,
        baseTokenAddress,
      ];
      spenders = [
        ...spenders,
        balancerVault.address,
        balancerVault.address,
        baseTokenPool,
      ];

      baseTokenRoots.map((root) => {
        if (root.name === "ETH") return;

        tokens = [...tokens, root.token.address];
        spenders = [...spenders, baseTokenPool];

        if (root.kind === RootTokenKind.LpToken) {
          root.roots.map((nestedRoot) => {
            if (root.name === "ETH") return;
            (tokens = [...tokens, nestedRoot.token.address]),
              (spenders = [...spenders, root.pool]);
          });
        }
      });

      return {
        tokens,
        spenders,
      };
    },
    {
      tokens: [] as string[],
      spenders: [] as string[],
    }
  );

  await zapCurveTokenToPrincipalToken.setApprovalsFor(tokenAddresses, spenders);

  const { tokens, whales } = [
    ePyvcrvSTETH,
    ePyvcrv3crypto,
    ePyvCurveLUSD,
  ].reduce(
    ({ tokens, whales }, trie) => {
      const tokenAddress = () => tokens.map((token) => token.address);
      const baseTokenRoots = trie.baseToken.roots;
      baseTokenRoots.map((root) => {
        if (root.whale && !tokenAddress().includes(root.token.address)) {
          tokens = [...tokens, root.token] as IERC20[];
          whales = [...whales, root.whale];
        }

        if (root.kind === RootTokenKind.LpToken) {
          root.roots.map((nestedRoot) => {
            if (
              root.whale &&
              !tokenAddress().includes(nestedRoot.token.address)
            ) {
              tokens = [...tokens, nestedRoot.token] as IERC20[];
              whales = [...whales, nestedRoot.whale] as string[];
            }
          });
        }
      });

      return {
        tokens,
        whales,
      };
    },
    {
      tokens: [] as IERC20[],
      whales: [] as string[],
    }
  );

  await Promise.all([
    ...tokens.map(async (token, idx) => {
      const whaleAddress = whales[idx];
      const whaleBalance = await token.balanceOf(whaleAddress);
      if (whaleBalance.eq(0)) return;
      const whaleSigner = await impersonate(whaleAddress);
      await token.connect(whaleSigner).transfer(user.address, whaleBalance);
      await stopImpersonating(whaleAddress);

      // enable approvals on root token for zapping in
      await token
        .connect(user.user)
        .approve(zapCurveTokenToPrincipalToken.address, whaleBalance);
    }),
    ...[ePyvcrv3crypto, ePyvcrvSTETH, ePyvCurveLUSD].map(
      async (trie) =>
        await trie.token
          .connect(user.user)
          .approve(
            zapCurveTokenToPrincipalToken.address,
            ethers.constants.MaxUint256
          )
    ),
  ] as Promise<any>[]);

  return {
    zapCurveTokenToPrincipalToken,
    balancerVault,
    ePyvcrvSTETH,
    ePyvcrv3crypto,
    ePyvCurveLUSD,
  };
}

const buildCurvePoolContract = (address: string, numRoots: number) => {
  return new ethers.Contract(
    address,
    [
      numRoots === 2
        ? "function calc_token_amount(uint256[2],bool) view returns (uint256)"
        : "function calc_token_amount(uint256[3],bool) view returns (uint256)",
    ],
    provider
  );
};

async function estimateZapIn(
  trie: PrincipalTokenCurveTrie,
  balancerVault: Vault,
  zap: ZapCurveLpInStruct,
  childZaps: ZapCurveLpInStruct[]
): Promise<BigNumber> {
  for (const childZap of childZaps) {
    const parentIdx = BigNumber.from(childZap.parentIdx).toNumber();
    const estimatedLpAmount = BigNumber.from(
      await buildCurvePoolContract(
        childZap.curvePool,
        childZap.amounts.length
      ).calc_token_amount(childZap.amounts, true)
    );

    zap.amounts[parentIdx] = BigNumber.from(zap.amounts[parentIdx])
      .add(estimatedLpAmount)
      .toString();
  }

  const baseTokenAmount = await buildCurvePoolContract(
    zap.curvePool,
    zap.amounts.length
  ).calc_token_amount(zap.amounts, true);

  const [convergentCurvePoolAddress] = await balancerVault.getPool(
    trie.balancerPoolId
  );

  const [, [xReserves, yReserves]] = await balancerVault.getPoolTokens(
    trie.balancerPoolId
  );

  const convergentCurvePool = ConvergentCurvePool__factory.connect(
    convergentCurvePoolAddress,
    balancerVault.signer
  );
  const totalSupply: BigNumber = await convergentCurvePool.totalSupply();
  const estimatedPtAmount: BigNumber =
    await convergentCurvePool.solveTradeInvariant(
      baseTokenAmount,
      xReserves,
      yReserves.add(totalSupply),
      true
    );

  const slippageAmount = calcBigNumberPercentage(
    estimatedPtAmount,
    trie.slippagePercentage
  );

  return estimatedPtAmount.sub(slippageAmount);
}

export async function constructZapInArgs(
  trie: PrincipalTokenCurveTrie,
  amounts: { [tokenName in string]: BigNumber },
  balancerVault: Vault,
  recipient: string
): Promise<{
  info: ZapInInfoStruct;
  zap: ZapCurveLpInStruct;
  childZaps: ZapCurveLpInStruct[];
  expectedPrincipalTokenAmount: BigNumber;
}> {
  const rootNames = trie.baseToken.roots
    .map((root) => [
      root.name,
      ...(root.kind === RootTokenKind.Basic
        ? []
        : root.roots.map((nestedRoot) => nestedRoot.name)),
    ])
    .flat();

  for (const n of Object.keys(amounts)) {
    if (!rootNames.includes(n)) {
      throw new Error(`Token ${n} does not exist in ${trie.name} trie`);
    }
  }

  const zap: () => ZapCurveLpInStruct = () => ({
    curvePool: trie.baseToken.pool,
    lpToken: trie.baseToken.token.address,
    amounts: trie.baseToken.roots.map((root) =>
      BigNumber.isBigNumber(amounts[root.name]) ? amounts[root.name] : ZERO
    ),
    roots: trie.baseToken.roots.map((root) => root.token.address),
    parentIdx: 0,
  });

  const childZaps: ZapCurveLpInStruct[] = trie.baseToken.roots
    .map((root, idx) => {
      if (root.kind !== RootTokenKind.LpToken) {
        return {} as ZapCurveLpInStruct;
      } else {
        return {
          curvePool: root.pool,
          lpToken: root.token.address,
          amounts: root.roots.map((r) =>
            BigNumber.isBigNumber(amounts[r.name]) ? amounts[r.name] : ZERO
          ),
          roots: root.roots.map((r) => r.token.address),
          parentIdx: idx,
        };
      }
    })
    .filter((zap) => Object.keys(zap).length !== 0);

  const expectedPrincipalTokenAmount = await estimateZapIn(
    trie,
    balancerVault,
    zap(),
    childZaps
  );

  const info: ZapInInfoStruct = {
    balancerPoolId: trie.balancerPoolId,
    principalToken: trie.token.address,
    recipient,
    minPtAmount: expectedPrincipalTokenAmount,
    deadline: Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS,
  };

  return {
    zap: zap(),
    childZaps,
    info,
    expectedPrincipalTokenAmount,
  };
}

// export async function constructZapOutArgs(
//   trie: PrincipalTokenCurveTrie,
//   target: string,
//   principalTokenAmount: BigNumber,
//   balancerVault: Vault,
//   recipient: string
// ): Promise<{
//   info: ZapOutInfoStruct;
//   zap: ZapCurveLpOutStruct;
//   //childZap: ZapCurveLpOutStruct;
//   //expectedTargetTokenAmount: BigNumber;
// }> {
//   const info: ZapOutInfoStruct = {
//     balancerPoolId: trie.balancerPoolId,
//     principalToken: trie.token.address,
//     recipient,
//     minPtAmount: 0,
//     deadline: Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS,
//     principalTokenAmount,
//   };

//   const zap: ZapCurveLpOutStruct = {
//     curvePool: trie.baseToken.pool,
//     lpToken: trie.baseToken.token.address,
//     targetIdx: 0,
//     targetToken: trie.baseToken.roots[0].token.address,
//     hasChildZap: false,
//   };

//   return {
//     info,
//     zap,
//   };
// }
