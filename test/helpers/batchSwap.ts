import { BytesLike } from "@ethersproject/bytes";
import { BigNumberish } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { ERC20 } from "typechain/ERC20";
import {
  BatchSwapStepStruct,
  FundManagementStruct,
  Vault,
} from "typechain/Vault";

import { ONE_DAY_IN_SECONDS } from "./time";

export enum SwapKind {
  GIVEN_IN,
  GIVEN_OUT,
}

export async function queryBatchSwapIn(
  tokenInContract: ERC20,
  tokenOutContract: ERC20,
  poolId: BytesLike,
  sender: string,
  balancerVaultContract: Vault,
  swapInAmount: string
) {
  const { swaps, tokens, funds } = await getBatchSwapArgs(
    tokenInContract,
    tokenOutContract,
    swapInAmount,
    poolId,
    sender
  );

  const swapReceipt = await balancerVaultContract.queryBatchSwap(
    SwapKind.GIVEN_IN,
    swaps,
    tokens,
    funds
  );

  await swapReceipt.wait(1);
  return swapReceipt;
}

export async function batchSwapIn(
  tokenInContract: ERC20,
  tokenOutContract: ERC20,
  poolId: BytesLike,
  sender: string,
  balancerVaultContract: Vault,
  swapInAmount: string
) {
  const { swaps, tokens, funds, limits, deadline } = await getBatchSwapArgs(
    tokenInContract,
    tokenOutContract,
    swapInAmount,
    poolId,
    sender
  );

  const swapReceipt = await balancerVaultContract.batchSwap(
    SwapKind.GIVEN_IN,
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
  poolId: BytesLike,
  sender: string
) {
  const tokens: string[] = [tokenInContract.address, tokenOutContract.address];
  const tokenInDecimals = await tokenInContract.decimals();
  const amount = parseUnits(swapInAmount, tokenInDecimals);

  // the series of swaps to perform, only one in this case.
  const swaps: BatchSwapStepStruct[] = [
    {
      poolId,
      // indices from 'tokens', putting FYTs in, getting base asset out.
      assetInIndex: 0,
      assetOutIndex: 1,
      amount,
      userData: poolId,
    },
  ];

  // trading with ourselves.  internal balance means internal to balancer.  we don't have anything
  // in there to start, but we'll keep whatever base assets we get from swapping in the balancer vault.
  const funds: FundManagementStruct = {
    sender,
    fromInternalBalance: false,
    recipient: sender,
    toInternalBalance: false,
  };

  // the user is sending this one, so the delta will be negative, so just set a limit of zero.
  const limitTokenIn = amount;

  // swapping in, so we can specify exactly how much in and set the limit to that.
  const limitTokenOut = amount;

  // limits of how much of each token is allowed to be traded.  order must be the same as 'tokens'
  const limits: BigNumberish[] = [limitTokenIn, limitTokenOut];

  // set a large deadline for now, it was being buggy.  time is in seconds.  must be an integer.
  const deadline = Math.round(Date.now() / 1000) + ONE_DAY_IN_SECONDS;
  return { swaps, tokens, funds, limits, deadline };
}
