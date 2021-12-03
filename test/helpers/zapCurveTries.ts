import { Signer } from "ethers";
import { waffle } from "hardhat";
import { IERC20__factory } from "typechain/factories/IERC20__factory";
import { Tranche__factory } from "typechain/factories/Tranche__factory";
import { IERC20 } from "typechain/IERC20";
import { Tranche } from "typechain/Tranche";
import { _ETH_CONSTANT } from "./constants";

const { provider } = waffle;

export interface PrincipalTokenCurveTrie {
  name: string;
  address: string;
  slippageInPercentage: number;
  slippageOutPercentage: number;
  balancerPoolId: string;
  baseToken: BaseTokenTrie;
}

type BaseTokenTrie = {
  name: string;
  address: string;
} & CurvePoolInfo &
  (
    | TwoRootTokens<RootTokenKind.Basic | RootTokenKind.LpToken>
    | ThreeRootTokens<RootTokenKind.Basic | RootTokenKind.LpToken>
  );

interface CurvePoolInfo {
  pool: string;
  zapInFuncSig: string;
  zapOutFuncSig: string;
}

export enum RootTokenKind {
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

export type RootToken<K extends RootTokenKind> = {
  name: string;
  address: string;
} & (K extends RootTokenKind.Basic
  ? { kind: RootTokenKind.Basic }
  : {
      kind: RootTokenKind.LpToken;
    } & CurvePoolInfo &
      (
        | TwoRootTokens<RootTokenKind.Basic>
        | ThreeRootTokens<RootTokenKind.Basic>
      ));

export const ePyvcrvSTETH: PrincipalTokenCurveTrie = {
  name: "ePyvcrvSTETH",
  address: "0x2361102893CCabFb543bc55AC4cC8d6d0824A67E",
  slippageInPercentage: 0.2,
  slippageOutPercentage: 0.75,
  balancerPoolId:
    "0xb03c6b351a283bc1cd26b9cf6d7b0c4556013bdb0002000000000000000000ab",
  baseToken: {
    name: "stCRV",
    address: "0x06325440D014e39736583c165C2963BA99fAf14E",
    pool: "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022",
    zapInFuncSig: "add_liquidity(uint256[2],uint256)",
    zapOutFuncSig: "remove_liquidity_one_coin(uint256,int128,uint256)",
    numberOfRoots: 2,
    roots: [
      {
        kind: RootTokenKind.Basic,
        name: "ETH",
        address: _ETH_CONSTANT,
      },
      {
        kind: RootTokenKind.Basic,
        name: "stETH",
        address: "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",
      },
    ],
  },
};

export const ePyvcrv3crypto: PrincipalTokenCurveTrie = {
  name: "ePyvcrv3crypto",
  address: "0x285328906D0D33cb757c1E471F5e2176683247c2",
  slippageInPercentage: 1,
  slippageOutPercentage: 1.2,
  balancerPoolId:
    "0x6dd0f7c8f4793ed2531c0df4fea8633a21fdcff40002000000000000000000b7",
  baseToken: {
    name: "crvTriCrypto",
    address: "0xc4AD29ba4B3c580e6D59105FFf484999997675Ff",
    pool: "0xD51a44d3FaE010294C616388b506AcdA1bfAAE46",
    zapInFuncSig: "add_liquidity(uint256[3],uint256)",
    zapOutFuncSig: "remove_liquidity_one_coin(uint256,uint256,uint256)",
    numberOfRoots: 3,
    roots: [
      {
        kind: RootTokenKind.Basic,
        name: "USDT",
        address: "0xdac17f958d2ee523a2206206994597c13d831ec7",
      },
      {
        kind: RootTokenKind.Basic,
        name: "WBTC",
        address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
      },
      {
        kind: RootTokenKind.Basic,
        name: "WETH",
        address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      },
    ],
  },
};

export const ePyvCurveLUSD: PrincipalTokenCurveTrie = {
  name: "ePyvCurveLUSD",
  address: "0xa2b3d083AA1eaa8453BfB477f062A208Ed85cBBF",
  slippageInPercentage: 0.075,
  slippageOutPercentage: 0.075,
  balancerPoolId:
    "0x893b30574bf183d69413717f30b17062ec9dfd8b000200000000000000000061",
  baseToken: {
    name: "LUSD3CRV_F",
    address: "0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA",
    pool: "0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA",
    zapInFuncSig: "add_liquidity(uint256[2],uint256)",
    zapOutFuncSig: "remove_liquidity_one_coin(uint256,int128,uint256)",
    numberOfRoots: 2,
    roots: [
      {
        kind: RootTokenKind.Basic,
        name: "LUSD",
        address: "0x5f98805A4E8be255a32880FDeC7F6728C6568bA0",
      },
      {
        kind: RootTokenKind.LpToken,
        name: "3Crv",
        address: "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490",
        pool: "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
        zapInFuncSig: "add_liquidity(uint256[3],uint256)",
        zapOutFuncSig: "remove_liquidity_one_coin(uint256,int128,uint256)",
        numberOfRoots: 3,
        roots: [
          {
            kind: RootTokenKind.Basic,
            name: "DAI",
            address: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
          },
          {
            kind: RootTokenKind.Basic,
            name: "USDC",
            address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
          },
          {
            kind: RootTokenKind.Basic,
            name: "USDT",
            address: "0xdac17f958d2ee523a2206206994597c13d831ec7",
          },
        ],
      },
    ],
  },
};

const zapCurveTries = [ePyvcrv3crypto, ePyvcrvSTETH, ePyvCurveLUSD];

export const zapCurveTrieAddresses = () =>
  zapCurveTries.reduce(
    (acc, trie) => ({
      ...acc,
      ...getPrincipalTokenAddress(trie),
      ...getBaseTokenAddress(trie),
      ...getRootTokensAddresses(trie),
    }),
    {} as { [k in string]: string }
  );

const getPrincipalTokenAddress = (trie: PrincipalTokenCurveTrie) => ({
  [trie.name]: trie.address,
});

const getBaseTokenAddress = (trie: PrincipalTokenCurveTrie) => ({
  [trie.baseToken.name]: trie.baseToken.address,
});

export const getRootTokensAddresses = (
  trie: PrincipalTokenCurveTrie
): { [k in string]: string } =>
  trie.baseToken.roots.reduce(
    (acc, root) => ({
      ...acc,
      [root.name]: root.address,
      ...(root.kind === RootTokenKind.LpToken
        ? root.roots.reduce(
            (_acc, _root) => ({ ..._acc, [_root.name]: _root.address }),
            {} as { [k in string]: string }
          )
        : {}),
    }),
    {} as { [k in string]: string }
  );

export const getERC20 = (name: string, signer?: Signer): IERC20 => {
  if (name === "ETH") {
    throw new Error("ETH is not an ERC20");
  }

  if (!zapCurveTrieAddresses()[name]) {
    throw new Error(`${name} does not exist`);
  }

  return IERC20__factory.connect(
    zapCurveTrieAddresses()[name],
    signer ?? provider
  );
};

export const getPrincipalToken = (name: string, signer?: Signer): Tranche => {
  if (!zapCurveTries.map(({ name }) => name).includes(name))
    throw new Error(`${name} does not exist`);

  return Tranche__factory.connect(
    zapCurveTrieAddresses()[name],
    signer ?? provider
  );
};
const getTrieApprovalsList = (
  trie: PrincipalTokenCurveTrie,
  zapContract: string
): { tokens: string[]; spenders: string[] } => {
  const balancerVaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";

  let tokens: string[] = [];
  let spenders: string[] = [];

  // Allow balancerVault to swap baseToken for principalToken when zapping in
  tokens = [...tokens, trie.baseToken.address];
  spenders = [...spenders, balancerVaultAddress];

  // Allow balancerVault to swap principalToken for baseToken for zapping out
  tokens = [...tokens, trie.address];
  spenders = [...spenders, balancerVaultAddress];

  // Allow respective curvePool to swap baseToken for a root for zapping out
  tokens = [...tokens, trie.baseToken.address];
  spenders = [...spenders, trie.baseToken.pool];

  trie.baseToken.roots.forEach((root) => {
    if (root.name !== "ETH") {
      // Allow first layer root to be swapped on the baseToken curvePool when zapping in
      tokens = [...tokens, root.address];
      spenders = [...spenders, trie.baseToken.pool];

      // Allow zapContract to send tokens to itself
      tokens = [...tokens, root.address];
      spenders = [...spenders, zapContract];

      if (root.kind === RootTokenKind.LpToken) {
        // If root is an lpToken with nested roots, allow itself on its pool to zap
        // to a nested root when zapping out
        tokens = [...tokens, root.address];
        spenders = [...spenders, root.pool];

        root.roots.forEach((nestedRoot) => {
          if (root.name !== "ETH") {
            // Where a root has nested roots, allow them on the root pool so they can
            // be swapped for the root lp token when a zapping in
            tokens = [...tokens, nestedRoot.address];
            spenders = [...spenders, root.pool];

            // Allow zapContract to send tokens to itself
            tokens = [...tokens, nestedRoot.address];
            spenders = [...spenders, zapContract];
          }
        });
      }
    }
  });

  return { tokens, spenders };
};

export const getZapContractApprovalsList = (zapContract: string) =>
  [
    ...new Set(
      zapCurveTries
        .map((trie) => {
          const { tokens, spenders } = getTrieApprovalsList(trie, zapContract);
          return tokens.map((tkn, idx) => `${tkn}-${spenders[idx]}`);
        })
        .flat()
    ),
  ]
    .map((x) => x.split("-"))
    .reduce(
      ({ tokens, spenders }, [token, spender]) => ({
        tokens: [...tokens, token],
        spenders: [...spenders, spender],
      }),
      { tokens: [], spenders: [] } as { tokens: string[]; spenders: string[] }
    );
