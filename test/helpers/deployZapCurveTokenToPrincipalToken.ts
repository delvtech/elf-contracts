import { BigNumber, Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { ConvergentCurvePool__factory } from "typechain/factories/ConvergentCurvePool__factory";
import { IERC20__factory } from "typechain/factories/IERC20__factory";
import { UserProxy__factory } from "typechain/factories/UserProxy__factory";
import { Vault__factory } from "typechain/factories/Vault__factory";
import { ZapCurveTokenToPrincipalToken__factory } from "typechain/factories/ZapCurveTokenToPrincipalToken__factory";
import { Vault } from "typechain/Vault";
import {
  ZapCurveLpInStruct,
  ZapCurveLpOutStruct,
  ZapInInfoStruct,
  ZapOutInfoStruct,
} from "typechain/ZapCurveTokenToPrincipalToken";
import { ZERO } from "./constants";
import { impersonate, stopImpersonating } from "./impersonate";
import { calcBigNumberPercentage } from "./math";
import { ONE_DAY_IN_SECONDS } from "./time";
import {
  getERC20,
  getPrincipalToken,
  getRootTokenAddresses,
  getZapContractApprovalsList,
  PrincipalTokenCurveTrie,
  RootToken,
  RootTokenKind,
} from "./zapCurveTries";

const { provider } = waffle;

export type ConstructZapInArgs = (
  trie: PrincipalTokenCurveTrie,
  amounts: { [tokenName in string]: BigNumber }
) => Promise<{
  info: ZapInInfoStruct;
  zap: ZapCurveLpInStruct;
  childZap: ZapCurveLpInStruct;
  expectedPrincipalTokenAmount: BigNumber;
}>;

export type ConstructZapOutArgs = (
  trie: PrincipalTokenCurveTrie,
  target: string,
  amount: BigNumber,
  recipient?: string,
  setAllowance?: boolean
) => Promise<{
  info: ZapOutInfoStruct;
  zap: ZapCurveLpOutStruct;
  childZap: ZapCurveLpOutStruct;
  expectedRootTokenAmount: BigNumber;
}>;

export async function deploy(user: { user: Signer; address: string }) {
  const [authSigner] = await ethers.getSigners();

  const balancerVault = Vault__factory.connect(
    "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    user.user
  );

  const proxy = UserProxy__factory.connect(
    "0xEe4e158c03A10CBc8242350d74510779A364581C",
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

  const { tokens, spenders } = getZapContractApprovalsList(
    zapCurveTokenToPrincipalToken.address
  );

  await zapCurveTokenToPrincipalToken.setApprovalsFor(
    tokens,
    spenders,
    Array.from(
      { length: spenders.length },
      () => ethers.constants.MaxUint256
    ) as BigNumber[]
  );

  await Promise.all(
    [...new Set(tokens)].map(async (token) =>
      IERC20__factory.connect(token, user.user).approve(
        zapCurveTokenToPrincipalToken.address,
        ethers.constants.MaxUint256
      )
    )
  );

  const constructZapInArgs: ConstructZapInArgs = async (trie, amounts) => {
    await Promise.all(
      Object.keys(getRootTokenAddresses(trie)).map(async (n) =>
        amounts[n] && amounts[n].eq(ZERO)
          ? await 0
          : await stealFromWhale(n, user.address)
      )
    );

    const zap: ZapCurveLpInStruct = {
      curvePool: trie.baseToken.pool,
      lpToken: trie.baseToken.address,
      amounts: trie.baseToken.roots.map((root) =>
        BigNumber.isBigNumber(amounts[root.name]) ? amounts[root.name] : ZERO
      ),
      roots: trie.baseToken.roots.map((root) => root.address),
      parentIdx: 0,
      minLpAmount: 0,
    };

    const lpRootIdx = trie.baseToken.roots.findIndex(
      (root) => root.kind === RootTokenKind.LpToken
    );

    let childZap: ZapCurveLpInStruct;
    if (lpRootIdx === -1) {
      childZap = zap;
    } else {
      const lpRoot = trie.baseToken.roots[
        lpRootIdx
      ] as RootToken<RootTokenKind.LpToken>;
      childZap = {
        curvePool: lpRoot.pool,
        lpToken: lpRoot.address,
        amounts: lpRoot.roots.map((r) =>
          BigNumber.isBigNumber(amounts[r.name]) ? amounts[r.name] : ZERO
        ),
        roots: lpRoot.roots.map((r) => r.address),
        parentIdx: lpRootIdx,
        minLpAmount: 0,
      };
    }

    const info: ZapInInfoStruct = {
      balancerPoolId: trie.balancerPoolId,
      principalToken: trie.address,
      recipient: user.address,
      minPtAmount: ZERO,
      deadline: Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS,
    };

    const expectedPrincipalTokenAmount = await estimateZapIn(
      trie,
      balancerVault,
      zap,
      childZap
    );

    return {
      zap,
      childZap,
      info: { ...info, minPtAmount: expectedPrincipalTokenAmount },
      expectedPrincipalTokenAmount,
    };
  };

  const constructZapOutArgs: ConstructZapOutArgs = async (
    trie,
    target,
    amount,
    recipient = user.address
  ) => {
    if (!Object.keys(getRootTokenAddresses(trie)).includes(target)) {
      throw new Error(`${target} is not a root token of ${trie.name}`);
    }
    await stealFromWhale(trie.baseToken.name, user.address);
    const baseToken = getERC20(trie.baseToken.name, user.user);
    const baseTokenAmount = await baseToken.balanceOf(user.address);
    await baseToken.approve(proxy.address, baseTokenAmount);
    const principalToken = getPrincipalToken(trie.name);
    const position = await principalToken.position();
    const expiration = await principalToken.unlockTimestamp();
    await proxy.mint(
      baseTokenAmount,
      baseToken.address,
      expiration,
      position,
      []
    );

    const userPrincipalTokenBalance = await principalToken.balanceOf(
      user.address
    );

    if (userPrincipalTokenBalance.lt(amount))
      throw new Error("Not enough pt's minted");

    const zapTokenIdx = trie.baseToken.roots.findIndex(
      (root) =>
        root.name === target ||
        (root.kind === RootTokenKind.LpToken &&
          root.roots.map((r) => r.name).includes(target))
    );

    const childZapRoot =
      zapTokenIdx !== -1 &&
      trie.baseToken.roots[zapTokenIdx].kind === RootTokenKind.LpToken &&
      trie.baseToken.roots[zapTokenIdx].name !== target
        ? (trie.baseToken.roots[
            zapTokenIdx
          ] as RootToken<RootTokenKind.LpToken>)
        : undefined;

    const childZapTokenIdx = childZapRoot
      ? childZapRoot.roots.findIndex((r) => r.name === target)
      : 0;

    if (zapTokenIdx === -1) {
      throw new Error("Could not assign zapTokenIdx");
    }

    const info: ZapOutInfoStruct = {
      balancerPoolId: trie.balancerPoolId,
      principalToken: trie.address,
      recipient,
      minRootTokenAmount: 0,
      minBaseTokenAmount: 0,
      deadline: Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS,
      principalTokenAmount: amount,
    };

    const zap: ZapCurveLpOutStruct = {
      curvePool: trie.baseToken.pool,
      isSigUint256:
        trie.baseToken.zapOutFuncSig ===
        "remove_liquidity_one_coin(uint256,uint256,uint256)",
      lpToken: trie.baseToken.address,
      rootTokenIdx: zapTokenIdx,
      rootToken: trie.baseToken.roots[zapTokenIdx].address,
    };

    const childZap: ZapCurveLpOutStruct =
      childZapRoot === undefined
        ? zap
        : {
            curvePool: childZapRoot.pool,
            isSigUint256:
              trie.baseToken.zapOutFuncSig ===
              "remove_liquidity_one_coin(uint256,uint256,uint256)",
            lpToken: childZapRoot.address,
            rootTokenIdx: childZapTokenIdx,
            rootToken: childZapRoot.roots[childZapTokenIdx].address,
          };

    const expectedRootTokenAmount = await estimateZapOut(
      trie,
      balancerVault,
      info,
      zap,
      childZap
    );

    return {
      info: { ...info, minRootTokenAmount: expectedRootTokenAmount },
      zap,
      childZap,
      expectedRootTokenAmount,
    };
  };

  return {
    zapCurveTokenToPrincipalToken,
    constructZapInArgs,
    constructZapOutArgs,
  };
}

const buildCurvePoolContract = ({
  address,
  numRoots = 2,
  targetType = `uint256`,
}: {
  address: string;
  numRoots?: number;
  targetType?: "uint256" | "int128";
}) => {
  return new ethers.Contract(
    address,
    [
      numRoots === 2
        ? "function calc_token_amount(uint256[2],bool) view returns (uint256)"
        : "function calc_token_amount(uint256[3],bool) view returns (uint256)",
      `function calc_withdraw_one_coin(uint256,${targetType}) view returns (uint256)`,
    ],
    provider
  );
};

async function estimateZapIn(
  trie: PrincipalTokenCurveTrie,
  balancerVault: Vault,
  zap: ZapCurveLpInStruct,
  childZap: ZapCurveLpInStruct
): Promise<BigNumber> {
  const estimatedLpAmount: BigNumber = !childZap.roots.every(
    (root, idx) => zap.roots[idx] === root
  )
    ? await buildCurvePoolContract({
        address: childZap.curvePool,
        numRoots: childZap.amounts.length,
      }).calc_token_amount(childZap.amounts, true)
    : ZERO;

  const zapAmounts = zap.amounts.map((amount, idx) =>
    idx === childZap.parentIdx ? estimatedLpAmount.add(amount) : amount
  );

  const baseTokenAmount = await buildCurvePoolContract({
    address: zap.curvePool,
    numRoots: zap.amounts.length,
  }).calc_token_amount(zapAmounts, true);

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
    trie.slippageInPercentage
  );

  return estimatedPtAmount.sub(slippageAmount);
}

async function estimateZapOut(
  trie: PrincipalTokenCurveTrie,
  balancerVault: Vault,
  info: ZapOutInfoStruct,
  zap: ZapCurveLpOutStruct,
  childZap: ZapCurveLpOutStruct
): Promise<BigNumber> {
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
  const estimatedBaseTokenAmount: BigNumber =
    await convergentCurvePool.solveTradeInvariant(
      info.principalTokenAmount,
      xReserves.add(totalSupply),
      yReserves,
      false
    );

  let estimatedRootTokenAmount: BigNumber = await buildCurvePoolContract({
    address: zap.curvePool,
    targetType: trie.name !== "ePyvcrv3crypto" ? "int128" : "uint256",
  }).calc_withdraw_one_coin(estimatedBaseTokenAmount, zap.rootTokenIdx);

  if (childZap.lpToken !== zap.lpToken) {
    estimatedRootTokenAmount = await buildCurvePoolContract({
      address: childZap.curvePool,
      targetType: trie.name !== "ePyvcrv3crypto" ? "int128" : "uint256",
    }).calc_withdraw_one_coin(estimatedRootTokenAmount, childZap.rootTokenIdx);
  }

  const slippageAmount = calcBigNumberPercentage(
    estimatedRootTokenAmount,
    trie.slippageOutPercentage
  );

  return estimatedRootTokenAmount.sub(slippageAmount);
}

export async function stealFromWhale(token: string, recipient: string) {
  if (token === "ETH") return;
  if (!whales[token]) {
    throw new Error("whale does not exist");
  }
  const whaleAddress = whales[token];
  const erc20 = getERC20(token);
  const whaleBalance = await erc20.balanceOf(whaleAddress);
  if (whaleBalance.eq(0)) {
    throw new Error("whale does not have balance");
  }

  const whaleSigner = await impersonate(whaleAddress);
  await erc20.connect(whaleSigner).transfer(recipient, whaleBalance);
  await stopImpersonating(whaleAddress);
}

const whales: { [k in string]: string } = {
  stCRV: "0x56c915758Ad3f76Fd287FFF7563ee313142Fb663",
  stETH: "0x06920C9fC643De77B99cB7670A944AD31eaAA260",
  crvTriCrypto: "0x26026fec6af3404a2d00918891966330bc2f36c8",
  USDT: "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
  WBTC: "0xE3DD3914aB28bB552d41B8dFE607355DE4c37A51",
  WETH: "0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3",
  LUSD3CRV_F: "0x3631401a11ba7004d1311e24d177b05ece39b4b3",
  LUSD: "0xE05fD1304C1CfE19dcc6AAb0767848CC4A8f54aa",
  "3Crv": "0x0B096d1f0ba7Ef2b3C7ecB8d4a5848043CdeBD50",
  DAI: "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
  USDC: "0xdb49552EeFB89416b9A412138c009a004f54BAd0",
};
