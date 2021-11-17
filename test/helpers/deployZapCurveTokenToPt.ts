import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumberish } from "ethers";
import { ethers } from "hardhat";
import { ValueOf } from "ts-essentials";
import { Vault__factory } from "typechain/factories/Vault__factory";
import { Tranche__factory } from "typechain/factories/Tranche__factory";
import { IERC20 } from "typechain/IERC20";
import { Tranche } from "typechain/Tranche";
import { Vault } from "typechain/Vault";
import {
  ZapCurveLpStruct,
  ZapPtInfoStruct,
  ZapTokenToPt,
} from "typechain/ZapTokenToPt";
import { ONE_DAY_IN_SECONDS } from "./time";
import { deployTrancheFactory } from "./deployer";
import { ZapTokenToPt__factory } from "typechain/factories/ZapTokenToPt__factory";
import data from "../../artifacts/contracts/Tranche.sol/Tranche.json";
import { IERC20__factory } from "typechain/factories/IERC20__factory";
import { type } from "os";
import { string } from "hardhat/internal/core/params/argumentTypes";
import { impersonate, stopImpersonating } from "./impersonate";

interface PrincipalCurveRoots {
  ep_yvcrvSTETH: {
    CRV_STETH: ["ETH", "STETH"];
  };
  ep_yvcrv3crypto: {
    THREE_CRV: ["DAI", "USDC", "USDT"];
  };
  ep_yvCurveLUSD: {
    LUSD_CRV: ["LUSD", { THREE_CRV: ["DAI", "USDC", "USDT"] }];
  };
}

export type PrincipalTokens = keyof PrincipalCurveRoots;

type PrincipalToken<P extends PrincipalTokens> = {
  [k in P]: Tranche;
};

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
  zapTrie: ZapTrie<P>;
  recipient: string;
  minPtAmount: BigNumberish;
  balancerPoolId: string;
} & TokenAmounts<P> &
  CurvePools<P> &
  TokenAddresses<P>;

type ZapStructs = {
  ptInfo: ZapPtInfoStruct;
  zap: ZapCurveLpStruct;
  childZaps: ZapCurveLpStruct[];
};

const buildZapStructs = <P extends PrincipalTokens>({
  amounts,
  pools,
  addresses,
  zapTrie,
  recipient,
  minPtAmount,
  balancerPoolId,
}: BuildZapStructsArgs<P>): ZapStructs => {
  const [principalToken, curveLpToken, directRootTokens, rootLpTokenRoots] =
    extractTrieLayers(zapTrie);

  const zap: ZapCurveLpStruct = {
    curvePool: pools[curveLpToken],
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

  const ptInfo: ZapPtInfoStruct = {
    balancerPoolId,
    principalToken: addresses[principalToken as TokenNames<P>],
    recipient,
    minPtAmount,
    deadline: Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS,
  };

  return {
    ptInfo,
    zap,
    childZaps,
  };
};

interface BuildZapCurveTokenFixtureConstructor {
  signer: SignerWithAddress;
  balancerVault: Vault;
  zapTokenToPt: ZapTokenToPt;
}

type ZapStructConstructor<P extends PrincipalTokens> = (
  amounts: TokenAmounts<P>["amounts"],
  recipient: string,
  minPtAmount: BigNumberish
) => ZapStructs;

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

const setZapApprovals = async <P extends PrincipalTokens>({
  zapTrie,
  zapTokenToPt,
  addresses,
  pools,
  balancerVault,
}: {
  balancerVault: Vault;
  zapTrie: ZapTrie<P>;
  zapTokenToPt: ZapTokenToPt;
} & TokenAddresses<P> &
  CurvePools<P>): Promise<void> => {
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

  await zapTokenToPt.setApprovalsFor(tokens, spenders);
};

export function buildZapCurveTokenFixtureConstructor<
  P extends PrincipalTokens
>({
  balancerVault,
  signer,
  zapTokenToPt,
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
      impersonate(whales[token]);
      await (tokens[token] as IERC20)
        .connect(ethers.provider.getSigner(whales[token]))
        .transfer(recipient, amount);
      stopImpersonating(whales[token]);
    };

    await setZapApprovals({
      balancerVault,
      addresses,
      zapTrie,
      pools,
      zapTokenToPt,
    });

    const constructZapStructs: ZapStructConstructor<P> = (
      amounts,
      recipient,
      minPtAmount
    ) =>
      buildZapStructs({
        amounts,
        zapTrie,
        addresses,
        pools,
        recipient,
        minPtAmount,
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
  zapTokenToPt: ZapTokenToPt;
  constructZapFixture: ZapCurveTokenFixtureConstructorFn;
}> {
  const [signer] = await ethers.getSigners();

  const balancerVault = Vault__factory.connect(
    "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    signer
  );
  const trancheFactory = await deployTrancheFactory(signer);
  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );

  const deployer = new ZapTokenToPt__factory(signer);
  const zapTokenToPt = await deployer.deploy(
    trancheFactory.address,
    bytecodehash,
    balancerVault.address
  );

  await zapTokenToPt.connect(signer).authorize(toAuth);
  await zapTokenToPt.connect(signer).setOwner(toAuth);

  const constructZapFixture = buildZapCurveTokenFixtureConstructor({
    signer,
    balancerVault,
    zapTokenToPt,
  });

  return {
    zapTokenToPt,
    constructZapFixture,
  };
}
