import { BytesLike } from "@ethersproject/bytes";
import { BigNumberish } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { ERC20 } from "typechain/ERC20";
import { Vault } from "typechain/Vault";

import { ONE_DAY_IN_SECONDS } from "./time";

export enum SwapKind {
  GIVEN_IN,
  GIVEN_OUT,
}

interface SwapIn {
  poolId: BytesLike;
  tokenInIndex: BigNumberish;
  tokenOutIndex: BigNumberish;
  amountIn: BigNumberish;
  userData: BytesLike;
}

interface FundManagement {
  sender: string;
  fromInternalBalance: boolean;
  recipient: string;
  toInternalBalance: boolean;
}

export async function queryBatchSwapIn(
  tokenInContract: ERC20,
  tokenOutContract: ERC20,
  poolId: string,
  sender: string,
  balancerVaultContract: Vault,
  swapInAmount: string
) {
  const {
    swaps,
    tokens,
    funds,
  }: {
    swaps: SwapIn[];
    tokens: string[];
    funds: FundManagement;
    limits: BigNumberish[];
    deadline: number;
  } = await getBatchSwapArgs(
    tokenInContract,
    tokenOutContract,
    swapInAmount,
    poolId,
    sender
  );

  const swapReceipt = await balancerVaultContract.queryBatchSwap(
    SwapKind.GIVEN_IN,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    swaps as any,
    tokens,
    funds
  );

  await swapReceipt.wait(1);
  return swapReceipt;
}

export async function batchSwapIn(
  tokenInContract: ERC20,
  tokenOutContract: ERC20,
  poolId: string,
  sender: string,
  balancerVaultContract: Vault,
  swapInAmount: string
) {
  const {
    swaps,
    tokens,
    funds,
    limits,
    deadline,
  }: {
    swaps: SwapIn[];
    tokens: string[];
    funds: FundManagement;
    limits: BigNumberish[];
    deadline: number;
  } = await getBatchSwapArgs(
    tokenInContract,
    tokenOutContract,
    swapInAmount,
    poolId,
    sender
  );

  const swapReceipt = await balancerVaultContract.batchSwapGivenIn(
    swaps,
    tokens,
    funds,
    limits,
    deadline
  );

  await swapReceipt.wait(1);
  return swapReceipt;
}

async function getBatchSwapArgs(
  tokenInContract: ERC20,
  tokenOutContract: ERC20,
  swapInAmount: string,
  poolId: string,
  sender: string
) {
  const tokens: string[] = [tokenInContract.address, tokenOutContract.address];
  const tokenInDecimals = await tokenInContract.decimals();
  const amountIn = parseUnits(swapInAmount, tokenInDecimals);
  // have to set this to something
  const userData: BytesLike = poolId;

  // the series of swaps to perform, only one in this case.
  const swaps: SwapIn[] = [
    {
      poolId,
      // indices from 'tokens', putting FYTs in, getting base asset out.
      tokenInIndex: 0,
      tokenOutIndex: 1,
      amountIn,
      userData,
    },
  ];

  // trading with ourselves.  internal balance means internal to balancer.  we don't have anything
  // in there to start, but we'll keep whatever base assets we get from swapping in the balancer vault.
  const funds: FundManagement = {
    sender,
    fromInternalBalance: false,
    recipient: sender,
    toInternalBalance: false,
  };

  // the user is sending this one, so the delta will be negative, so just set a limit of zero.
  const limitTokenIn = amountIn;

  // performing a SwapIn, so we can specify exactly how much in and set the limit to that.
  const limitTokenOut = amountIn;

  // limits of how much of each token is allowed to be traded.  order must be the same as 'tokens'
  const limits: BigNumberish[] = [limitTokenIn, limitTokenOut];

  // set a large deadline for now, it was being buggy.  time is in seconds.  must be an integer.
  const deadline = Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS;
  return { swaps, tokens, funds, limits, deadline };
}
