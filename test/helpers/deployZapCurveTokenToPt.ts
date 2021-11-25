import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, BigNumberish } from "ethers";
import { ethers, waffle } from "hardhat";
import { ValueOf } from "ts-essentials";
import { IERC20__factory } from "typechain/factories/IERC20__factory";
import { Tranche__factory } from "typechain/factories/Tranche__factory";
import { Vault__factory } from "typechain/factories/Vault__factory";
import { ZapCurveToPt__factory } from "typechain/factories/ZapCurveToPt__factory";
import { IERC20 } from "typechain/IERC20";
import { Tranche } from "typechain/Tranche";
import { Vault } from "typechain/Vault";
import { ZapCurveToPt } from "typechain/ZapCurveToPt";
import { ZapCurveLpStruct, ZapPtInfoStruct } from "typechain/ZapTokenToPt";
import { SwapKind } from "./batchSwap";
import { calcSwapPrincipalPool, SwapAsset } from "./calculations";
import { impersonate, stopImpersonating } from "./impersonate";
import { ONE_DAY_IN_SECONDS } from "./time";

const { provider } = waffle;

interface PrincipalCurveRoots {
  ePyvcrvSTETH: {
    stCRV: ["ETH", "stETH"];
  };
  ePyvcrv3crypto: {
    crvTriCrypto: ["USDT", "WBTC", "WETH"];
  };
  ePyvCurveLUSD: {
    LUSD3CRV_F: ["LUSD", { ThreeCrv: ["DAI", "USDC", "USDT"] }];
  };
}

export type PrincipalTokens = keyof PrincipalCurveRoots;
type PrincipalLpToken<P extends PrincipalTokens> = keyof PrincipalCurveRoots[P];

type LpToken<P extends PrincipalTokens> = PrincipalLpToken<P> | LpRootToken<P>;

type SimpleRootToken<P extends PrincipalTokens> = ValueOf<
  PrincipalCurveRoots[P]
> extends infer R
  ? R extends any[]
    ? R[number] extends infer J
      ? J extends string
        ? J
        : never
      : never
    : never
  : never;

type LpRootToken<P extends PrincipalTokens> = ValueOf<
  PrincipalCurveRoots[P]
> extends infer R
  ? R extends any[]
    ? R[number] extends infer J
      ? J extends string
        ? never
        : keyof J
      : never
    : never
  : never;

type LpRootTokenRoots<P extends PrincipalTokens> = ValueOf<
  PrincipalCurveRoots[P]
> extends infer R
  ? R extends any[]
    ? R[number] extends infer J
      ? J extends string
        ? []
        : ValueOf<J> extends any[]
        ? ValueOf<J>[number]
        : never
      : never
    : never
  : never;

type DirectRootToken<P extends PrincipalTokens> =
  | SimpleRootToken<P>
  | LpRootToken<P>;

type RootToken<P extends PrincipalTokens> =
  | DirectRootToken<P>
  | LpRootTokenRoots<P>;

type ZapTrie<P extends PrincipalTokens> = {
  [K in P]: {
    [R in PrincipalLpToken<P>]: ValueOf<PrincipalCurveRoots[P]>;
  };
};

type TokenNames<P extends PrincipalTokens> =
  | RootToken<P>
  | LpToken<P>
  | P extends infer R
  ? R extends string
    ? R
    : never
  : never;

type Tokens<P extends PrincipalTokens> = {
  [K in TokenNames<P>]: K extends "ETH"
    ? { address: string }
    : K extends PrincipalTokens
    ? Tranche
    : IERC20;
};

type UserTokens<P extends PrincipalTokens> =
  | RootToken<P>
  | LpRootToken<P> extends infer Token
  ? Token extends string
    ? Token
    : never
  : never;

type TokenAmounts<P extends PrincipalTokens> = {
  amounts: { [K in UserTokens<P>]: BigNumberish };
};
type TokenAddresses<P extends PrincipalTokens> = {
  addresses: { [K in TokenNames<P>]: string };
};

type TokenWhales<P extends PrincipalTokens> = {
  whales: { [K in Exclude<UserTokens<P>, "ETH">]: string };
};

type CurvePools<P extends PrincipalTokens> = {
  pools: { [K in LpToken<P>]: string };
};

const extractTrieLayers = <P extends PrincipalTokens>(
  zapTrie: ZapTrie<P>
): [P, PrincipalLpToken<P>, DirectRootToken<P>[], LpRootTokenRoots<P>[]] => {
  const [principalToken, curveTrie]: [P, PrincipalCurveRoots[P]] =
    Object.entries(zapTrie).flat() as any;

  const [curveLpToken, roots]: [
    PrincipalLpToken<P>,
    (SimpleRootToken<P> | { [k in LpRootToken<P>]: LpRootTokenRoots<P> })[]
  ] = Object.entries(curveTrie).flat() as any;

  const directRootTokens = roots.map((root) => {
    if (typeof root === "string") {
      return root;
    }
    return Object.keys(root)[0];
  }) as DirectRootToken<P>[];

  const rootLpTokenRoots = roots.map((root) => {
    if (typeof root !== "string") {
      return Object.values(root)[0];
    }
    return [];
  }) as LpRootTokenRoots<P>[];

  return [principalToken, curveLpToken, directRootTokens, rootLpTokenRoots];
};

type BuildZapStructsArgs<P extends PrincipalTokens> = {
  balancerVault: Vault;
  zapTrie: ZapTrie<P>;
  recipient: string;
  balancerPoolId: string;
} & TokenAmounts<P> &
  CurvePools<P> &
  TokenAddresses<P>;

async function estimateCurveZap({
  curvePool,
  amounts,
}: ZapCurveLpStruct): Promise<string> {
  const curveAbi = [
    "function fee() view returns (uint256)",
    amounts.length === 2
      ? "function calc_token_amount(uint256[2],bool) view returns (uint256)"
      : "function calc_token_amount(uint256[3],bool) view returns (uint256)",
  ];

  const curveContract = new ethers.Contract(curvePool, curveAbi, provider);
  const lpRawAmount = BigNumber.from(
    await curveContract.calc_token_amount(amounts, true)
  );
  const curveFee: BigNumberish = await curveContract.fee();

  const FEE_DENOMINATOR = BigNumber.from("10").pow(BigNumber.from("10"));
  const feeAmount = lpRawAmount.mul(curveFee).div(FEE_DENOMINATOR);

  return lpRawAmount.sub(feeAmount).toString();
}

async function estimatePtZap(
  balancerVault: Vault,
  amount: BigNumberish,
  balancerPoolId: string
): Promise<string> {
  const [convergentCurvePoolAddress] = await balancerVault.getPool(
    balancerPoolId
  );

  const ccpAbi = [
    "function expiration() view returns (uint256)",
    "function totalSupply() view returns (uint256)",
    "function unitSeconds() view returns (uint256)",
  ];

  const convergentCurvePool = new ethers.Contract(
    convergentCurvePoolAddress,
    ccpAbi,
    provider
  );

  const [totalSupply, expiration, tParamSeconds] = await Promise.all([
    convergentCurvePool.totalSupply(),
    convergentCurvePool.expiration(),
    convergentCurvePool.unitSeconds(),
  ] as Promise<BigNumberish>[]);

  const [, [xReserves, yReserves]] = await balancerVault.getPoolTokens(
    balancerPoolId
  );

  const result = calcSwapPrincipalPool(
    amount.toString(),
    SwapKind.GIVEN_IN,
    SwapAsset.BASE_ASSET,
    18,
    xReserves.toString(),
    yReserves.toString(),
    totalSupply.toString(),
    tParamSeconds.toString(),
    expiration.toString()
  );

  return result.amountOut;
}

type ZapStructs = {
  ptInfo: ZapPtInfoStruct;
  zap: ZapCurveLpStruct;
  childZaps: ZapCurveLpStruct[];
  expectedPtAmount: BigNumberish;
};

const buildZapStructs = async <P extends PrincipalTokens>({
  balancerVault,
  amounts,
  pools,
  addresses,
  zapTrie,
  recipient,
  balancerPoolId,
}: BuildZapStructsArgs<P>): Promise<ZapStructs> => {
  const [principalToken, curveLpToken, directRootTokens, rootLpTokenRoots] =
    extractTrieLayers(zapTrie);

  const zap: ZapCurveLpStruct = {
    curvePool: pools[curveLpToken],
    lpToken: addresses[curveLpToken as TokenNames<P>],
    amounts: directRootTokens.map((r) => amounts[r]),
    roots: directRootTokens.map((r) => addresses[r]),
    parentIdx: 0, // unused
  };

  const childZaps: ZapCurveLpStruct[] = directRootTokens
    .map(
      (root, idx) =>
        ((rootLpTokenRoots[idx] as any[]).length
          ? {
              curvePool: pools[root],
              lpToken: addresses[root],
              amounts: (rootLpTokenRoots[idx] as UserTokens<P>[]).map(
                (r) => amounts[r]
              ),
              roots: (rootLpTokenRoots[idx] as UserTokens<P>[]).map(
                (r) => addresses[r]
              ),
              parentIdx: idx,
            }
          : []) as ZapCurveLpStruct | []
    )
    .filter((zap) => !Array.isArray(zap)) as ZapCurveLpStruct[];

  for (const xZap of childZaps) {
    const parentIdx = BigNumber.from(xZap.parentIdx).toNumber();
    const amountString = await estimateCurveZap(xZap);
    zap.amounts[parentIdx] = BigNumber.from(zap.amounts[parentIdx]).add(
      BigNumber.from(amountString)
    );
  }

  const estimatedBaseTokenAmount = await estimateCurveZap(zap);
  const estimatedPrincipalTokenAmount = await estimatePtZap(
    balancerVault,
    BigNumber.from(estimatedBaseTokenAmount),
    balancerPoolId
  );

  console.log("Expected BaseToken Amount: ", estimatedBaseTokenAmount);
  console.log(
    "Expected PrincipalToken Amount: ",
    estimatedPrincipalTokenAmount
  );

  const ptInfo: ZapPtInfoStruct = {
    balancerPoolId,
    principalToken: addresses[principalToken as TokenNames<P>],
    recipient,
    minPtAmount: 0, //BigNumber.from(estimatedPrincipalTokenAmount),
    deadline: Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS,
  };

  return {
    ptInfo,
    zap,
    childZaps,
    expectedPtAmount: BigNumber.from(estimatedPrincipalTokenAmount),
  };
};

interface BuildZapCurveTokenFixtureConstructor {
  signer: SignerWithAddress;
  balancerVault: Vault;
  zapCurveToPt: ZapCurveToPt;
}

type ZapStructConstructor<P extends PrincipalTokens> = (
  amounts: TokenAmounts<P>["amounts"],
  recipient: string
) => Promise<ZapStructs>;

export interface ZapCurveTokenFixture<P extends PrincipalTokens> {
  constructZapStructs: ZapStructConstructor<P>;
  tokens: Tokens<P>;
  stealFromWhale: (x: {
    recipient: string;
    token: Exclude<UserTokens<P>, "ETH">;
    amount: BigNumberish;
  }) => Promise<void>;
}

export type ZapCurveTokenFixtureConstructorFn = <P extends PrincipalTokens>(
  x: {
    zapTrie: ZapTrie<P>;
    balancerPoolId: string;
  } & TokenAddresses<P> &
    CurvePools<P> &
    TokenWhales<P>
) => Promise<ZapCurveTokenFixture<P>>;

type SetZapApprovals<P extends PrincipalTokens> = {
  signer: SignerWithAddress;
  balancerVault: Vault;
  zapTrie: ZapTrie<P>;
  zapCurveToPt: ZapCurveToPt;
} & TokenAddresses<P> &
  CurvePools<P>;

const setZapApprovals = async <P extends PrincipalTokens>({
  signer,
  zapTrie,
  zapCurveToPt,
  addresses,
  pools,
  balancerVault,
}: SetZapApprovals<P>): Promise<void> => {
  const [_, curveLpToken, directRootTokens, rootLpTokenRoots] =
    extractTrieLayers(zapTrie);

  const [zapTokens, zapSpenders] = [
    directRootTokens.filter((token) => token !== "ETH"),
    directRootTokens.filter((token) => token !== "ETH").map(() => curveLpToken),
  ];

  const [childZapTokens, childZapSpenders] = directRootTokens
    .map((rootCurveLpToken, idx) =>
      (rootLpTokenRoots[idx] as any).length
        ? (rootLpTokenRoots[idx] as string[]).map((rToken) => [
            rToken,
            rootCurveLpToken,
          ])
        : []
    )
    .flat()
    .filter(([root]) => root !== "ETH")
    .reduce(
      (acc, [root, curve]) => {
        acc[0].push(root), acc[1].push(curve);
        return acc;
      },
      [[], []] as [string[], string[]]
    );

  const [tokens, spenders] = [
    [...zapTokens, ...childZapTokens, curveLpToken].map(
      (token) => addresses[token as TokenNames<P>]
    ),
    [
      ...[...zapSpenders, ...childZapSpenders].map(
        (token) => pools[token as TokenNames<P>]
      ),
      balancerVault.address,
    ],
  ];

  await zapCurveToPt.connect(signer).setApprovalsFor(tokens, spenders);
};

export function buildZapCurveTokenFixtureConstructor<
  P extends PrincipalTokens
>({
  balancerVault,
  signer,
  zapCurveToPt,
}: BuildZapCurveTokenFixtureConstructor): ZapCurveTokenFixtureConstructorFn {
  return async function ({
    zapTrie,
    balancerPoolId,
    addresses,
    pools,
    whales,
  }) {
    const tokens = (Object.entries(addresses) as [string, string][]).reduce(
      (acc, [tName, tAddress]) => {
        if (tName === "ETH") {
          return {
            ...acc,
            ETH: {
              address: tAddress,
            },
          };
        }
        const [ptName] = Object.keys(zapTrie);
        if (tName === ptName)
          return {
            ...acc,
            [ptName]: Tranche__factory.connect(tAddress, signer),
          };

        return {
          ...acc,
          [tName]: IERC20__factory.connect(tAddress, signer),
        };
      },
      {} as Tokens<P>
    );

    const stealFromWhale = async ({
      recipient,
      token,
      amount,
    }: {
      recipient: string;
      token: Exclude<UserTokens<P>, "ETH">;
      amount: BigNumberish;
    }) => {
      const whaleSigner = await impersonate(whales[token]);
      await (tokens[token] as IERC20)
        .connect(whaleSigner)
        .transfer(recipient, amount, { from: whales[token] });
      await stopImpersonating(whales[token]);
    };

    await setZapApprovals({
      signer,
      balancerVault,
      addresses,
      zapTrie,
      pools,
      zapCurveToPt,
    });

    const constructZapStructs: ZapStructConstructor<P> = async (
      amounts,
      recipient
    ) =>
      await buildZapStructs({
        balancerVault,
        amounts,
        zapTrie,
        addresses,
        pools,
        recipient,
        balancerPoolId,
      });

    return {
      constructZapStructs,
      tokens,
      stealFromWhale,
    };
  };
}

export async function deploy(toAuth: string): Promise<{
  zapCurveToPt: ZapCurveToPt;
  balancerVault: Vault;
  constructZapFixture: ZapCurveTokenFixtureConstructorFn;
}> {
  const [signer] = await ethers.getSigners();

  const balancerVault = Vault__factory.connect(
    "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    signer
  );

  const deployer = new ZapCurveToPt__factory(signer);
  const zapCurveToPt = await deployer.deploy(balancerVault.address);

  await zapCurveToPt.connect(signer).authorize(toAuth);
  await zapCurveToPt.connect(signer).setOwner(toAuth);

  const constructZapFixture = buildZapCurveTokenFixtureConstructor({
    signer,
    balancerVault,
    zapCurveToPt,
  });

  return {
    zapCurveToPt,
    balancerVault,
    constructZapFixture,
  };
}
