import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  calcSwapOutGivenInCCPoolUnsafe,
  getReserves,
  getSecondsUntilExpiration,
  getTotalSupply,
  getUnitSeconds,
} from "elf-sdk";
import { BigNumberish } from "ethers";
import { ethers } from "hardhat";
import { Tuple, ValueOf } from "ts-essentials";
import { BasePool } from "typechain/BasePool";
import { BasePool__factory } from "typechain/factories/BasePool__factory";
import { ICurveFi__factory } from "typechain/factories/ICurveFi__factory";
import { IERC20__factory } from "typechain/factories/IERC20__factory";
import { Tranche__factory } from "typechain/factories/Tranche__factory";
import { Vault__factory } from "typechain/factories/Vault__factory";
import { ZapTokenToPt__factory } from "typechain/factories/ZapTokenToPt__factory";
import { ICurveFi } from "typechain/ICurveFi";
import { IERC20 } from "typechain/IERC20";
import { Tranche } from "typechain/Tranche";
import { Vault } from "typechain/Vault";
import { ZapTokenToPt } from "typechain/ZapTokenToPt";
import data from "../../artifacts/contracts/Tranche.sol/Tranche.json";
import { deployTrancheFactory } from "./deployer";

// type Root2<T1, T2> = [T1, T2, ...never[]]
// type Root3<T1, T2, T3> = [T1, T2, T3, ...never[]]
// type Root = Root2<string, string> | Root3<string, string, string> | Root2<string, CurveTokenRootMap<string, Root3<string, string, string>>>

// type CurveTokenRootMap<C extends string, R extends Root> = { [K in C]: R }

// type CRVSTETH_LP = CurveTokenRootMap<"CRVSTETH", ["ETH", "STETH"]>
// type THREE_CRV_LP = CurveTokenRootMap<"THREE_CRV", ["DAI", "USDC", "USDT"]>
// type LUSD_THREE_CRV_LP = CurveTokenRootMap<"LUSD_THREE_CRV", ["LUSD", ["THREE_CRV", ]]>

// type FlattenRoot<T> = T extends string ? T : T extends Root ? FlattenRoot<T[number]> : never

// type ExtractRoots<T extends CurveTokenRootMap<string, Root>> = ValueOf<T> extends infer R ? R extends string ? R : R extends Root ? FlattenRoot<R> : never : never

// interface PrincipalCurveRoots {
//   epCrvSteth: {
//   },
//   epThreeCrv: {
//     threeCrv: ["DAI", "USDC", "USDT"]
//   },
//   epLusdThreeCrv: {
//     lusdThreeCrv: ["LUSD", { threeCrv: ["DAI", "USDC", "USDT"] }]
// }

//export type Roots = ValueOf<PrincipalRootTokenTuples>;
// type RootTokens<R extends Roots> = {
//   [K in R[number]]: K extends "ETH" ? { address: string } : IERC20;
// };

// type RootWhales<R extends Roots> = Omit<
//   {
//     [K in R[number] as `whale${K}`]: K extends "ETH" ? never : string;
//   },
//   "whaleETH"
// >;

// type PrincipalToken<P extends PrincipalTokens> = { [k in P]: Tranche };
// export type ZapCurveTokenFixture<P extends PrincipalTokens, R extends Roots> = {
//   curvePool: ICurveFi;
//   balancerPoolId: string;
//   convergentCurvePool: BasePool;
//   roots: R;
//   calcMinPtAmount: (amounts: BigNumberish[]) => Promise<number>;
// } & RootTokens<R> &
//   RootWhales<R> &
//   PrincipalToken<P>;

// export type ZapCurveTokenFixtures = {
//   [K in keyof PrincipalRootTokenTuples]: PrincipalRootTokenTuples[K] extends Roots
//     ? ZapCurveTokenFixture<K, PrincipalRootTokenTuples[K]>
//     : never;
// };

// export type ZapCurveTokenFixtureConstructorFn<
//   P extends PrincipalTokens,
//   R extends Roots
// > = (x: {
//   roots: R;
//   rootAddresses: string[];
//   rootWhales: (string | null)[];
//   curvePoolAddress: string;
//   principalTokenAddress: string;
//   balancerPoolId: string;
//   pt: PrincipalTokens;
// }) => Promise<ZapCurveTokenFixture<P, R>>;

// interface BuildZapCurveTokenFixtureConstructor {
//   signer: SignerWithAddress;
//   balancerVault: Vault;
//   zapTokenToPt: ZapTokenToPt;
// }

// export function buildZapCurveTokenFixtureConstructor<
//   P extends PrincipalTokens,
//   R extends Roots
// >({
//   signer,
//   balancerVault,
//   zapTokenToPt,
// }: BuildZapCurveTokenFixtureConstructor): ZapCurveTokenFixtureConstructorFn<
//   P,
//   R
// > {
//   return async function ({
//     roots,
//     rootAddresses,
//     rootWhales,
//     balancerPoolId,
//     curvePoolAddress,
//     principalTokenAddress,
//     pt,
//   }) {
//     const [convergentCurvePoolAddress] = await balancerVault.getPool(
//       balancerPoolId
//     );

//     const tokens = roots.reduce(
//       (acc, root, idx) => ({
//         ...acc,
//         [root]:
//           root === "ETH"
//             ? { address: rootAddresses[idx] }
//             : IERC20__factory.connect(rootAddresses[idx], signer),
//       }),
//       {} as RootTokens<R>
//     );

//     const whales = rootWhales.reduce((acc, whale, idx) => {
//       if (whale !== null) {
//         return { ...acc, [`whale${roots[idx]}`]: whale };
//       }
//       return acc;
//     }, {} as RootWhales<R>);

//     const curvePool = ICurveFi__factory.connect(curvePoolAddress, signer);

//     const baseToken = await curvePool.lp_token();

//     const erc20Tokens = rootAddresses.filter((_, idx) => roots[idx] !== "ETH");
//     await zapTokenToPt
//       .connect(signer)
//       .setApprovalsFor(
//         [baseToken, ...erc20Tokens],
//         [balancerVault.address, ...erc20Tokens.map(() => curvePoolAddress)]
//       );

//     const calcMinPtAmount = async (amounts: BigNumberish[]) => {
//       const xAmount: BigNumberish = await (
//         curvePool[
//           `calc_token_amount(uint256[${amounts.length === 2 ? 2 : 3}],bool)`
//         ] as any
//       )(amounts, false);

//       const [balancerPool] = await balancerVault.getPool(balancerPoolId);
//       const {
//         balances: [xReserves, yReserves],
//         tokens,
//       } = await getReserves(balancerPool, balancerVault.address, signer);

//       const totalSupply = await getTotalSupply(balancerPool, signer);
//       const nowInSeconds = Math.round(Date.now() / 1000);
//       const timeRemainingSeconds = await getSecondsUntilExpiration(
//         balancerPool,
//         signer,
//         nowInSeconds
//       );
//       const tParamsSeconds = await getUnitSeconds(balancerPool, signer);

//       console.log("xAmount:", xAmount.toString());
//       console.log("xReserves:", xReserves.toString());
//       console.log("yReserves", yReserves.toString());
//       console.log("totalSupply:", totalSupply.toString());
//       console.log("timeRemaining:", timeRemainingSeconds);
//       console.log("tParamsSeconds:", timeRemainingSeconds);
//       return calcSwapOutGivenInCCPoolUnsafe(
//         xAmount.toString(),
//         xReserves.toString(),
//         yReserves.toString(),
//         totalSupply.toString(),
//         timeRemainingSeconds,
//         tParamsSeconds,
//         true
//       );
//     };

//     return {
//       convergentCurvePool: BasePool__factory.connect(
//         convergentCurvePoolAddress,
//         signer
//       ),
//       curvePool,
//       calcMinPtAmount,
//       [pt]: Tranche__factory.connect(principalTokenAddress, signer),
//       balancerPoolId,
//       roots,
//       ...tokens,
//       ...whales,
//     };
//   };
// }

// export type ZapCurveTokenToPtFixture = {
//   zapTokenToPt: ZapTokenToPt;
//   constructZapCurveTokenFixture: ZapCurveTokenFixtureConstructorFn<
//     PrincipalTokens,
//     Roots
//   >;
// };

// export async function initZapCurveTokenToPt(
//   toAuth: string
// ): Promise<ZapCurveTokenToPtFixture> {
//   const [signer] = await ethers.getSigners();

//   const balancerVault = Vault__factory.connect(
//     "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
//     signer
//   );
//   const trancheFactory = await deployTrancheFactory(signer);
//   const bytecodehash = ethers.utils.solidityKeccak256(
//     ["bytes"],
//     [data.bytecode]
//   );

//   const deployer = new ZapTokenToPt__factory(signer);
//   const zapTokenToPt = await deployer.deploy(
//     trancheFactory.address,
//     bytecodehash,
//     balancerVault.address
//   );

//   await zapTokenToPt.connect(signer).authorize(toAuth);
//   await zapTokenToPt.connect(signer).setOwner(toAuth);

//   const constructZapCurveTokenFixture = buildZapCurveTokenFixtureConstructor({
//     signer,
//     balancerVault,
//     zapTokenToPt,
//   });

//   return {
//     zapTokenToPt,
//     constructZapCurveTokenFixture,
//   };
// }
