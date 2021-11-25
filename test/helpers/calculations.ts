import { BigNumber } from "ethers";
import { UnreachableCaseError } from "ts-essentials";
import { SwapKind } from "./batchSwap";
import { ZERO } from "./constants";

export enum PrincipalPoolCalcSwapError {
  INSUFFICENT_RESERVES = "INSUFFICIENT_RESERVES",
}
export interface PrincipalPoolCalcSwapResult {
  amountIn: string;
  amountOut: string;
  error?: PrincipalPoolCalcSwapError;
}

export enum SwapAsset {
  BASE_ASSET = "BASE_ASSET",
  PRINCIPAL_TOKEN = "PRINCIPAL_TOKEN",
}

function calcSwapCCPoolUNSAFE(
  xAmount: string,
  xReserves: string,
  yReserves: string,
  timeRemainingSeconds: number,
  tParamSeconds: number,
  getOutputQuote: boolean
): BigNumber {
  const amountX = BigNumber.from(xAmount);

  const xR = BigNumber.from(xReserves);
  const yR = BigNumber.from(yReserves);

  const t = BigNumber.from(timeRemainingSeconds).div(
    BigNumber.from(tParamSeconds)
  );

  const oneMinusT = BigNumber.from("1").sub(t);
  const xBefore = xR.pow(oneMinusT);
  const yBefore = yR.pow(oneMinusT);

  const xAfter = getOutputQuote
    ? xR.add(amountX).pow(oneMinusT)
    : xR.sub(amountX).pow(oneMinusT);

  // this is the real equation, make ascii art for it
  const yAfter = xBefore
    .add(yBefore)
    .sub(xAfter)
    .pow(BigNumber.from("1").div(oneMinusT));

  const amountY = getOutputQuote ? yR.sub(yAfter) : yAfter.sub(yR);

  return amountY;
}

export function calcSwapPrincipalPool(
  amountX: string,
  swapKind: SwapKind,
  swapAsset: SwapAsset,
  decimals: number,
  tokenInReserves: string,
  tokenOutReserves: string,
  totalSupply: string,
  tParamSeconds: string,
  expiration: string
): PrincipalPoolCalcSwapResult {
  // check for bad inputs, ie: 0 (including "0.0", et al) and empty strings
  const amount = BigNumber.from(amountX);
  if (!BigNumber.isBigNumber(amount) || amount.eq(ZERO)) {
    return { amountIn: "0", amountOut: "0" };
  }

  // After maturity, values trade 1-1
  const nowInSeconds = Math.round(Date.now() / 1000);
  const timeRemainingSeconds = Math.max(+expiration - nowInSeconds, 0);
  if (timeRemainingSeconds === 0) {
    return { amountIn: amount.toString(), amountOut: amount.toString() };
  }

  // Always add total supply to base asset reserves
  let adjustedInReserves = ZERO;
  let adjustedOutReserves = ZERO;
  switch (swapAsset) {
    case SwapAsset.BASE_ASSET: {
      adjustedInReserves = BigNumber.from(tokenInReserves);
      adjustedOutReserves = BigNumber.from(tokenOutReserves).add(
        BigNumber.from(totalSupply)
      );
      break;
    }
    case SwapAsset.PRINCIPAL_TOKEN: {
      adjustedInReserves = BigNumber.from(tokenInReserves).add(
        BigNumber.from(totalSupply)
      );
      adjustedOutReserves = BigNumber.from(tokenOutReserves);
      break;
    }
    default:
      throw new UnreachableCaseError("NEVER" as never);
  }

  switch (swapKind) {
    case SwapKind.GIVEN_IN: {
      const calcOutNumber = calcSwapCCPoolUNSAFE(
        amount.toString(),
        adjustedInReserves.toString(),
        adjustedOutReserves.toString(),
        timeRemainingSeconds,
        +tParamSeconds,
        true // swapKind === SwapKind.GIVEN_IN (calculate output)
      );

      // We get back NaN when there are insufficient reserves
      if (!calcOutNumber.toString()) {
        return {
          amountOut: "0",
          amountIn: amount.toString(),
          error: PrincipalPoolCalcSwapError.INSUFFICENT_RESERVES,
        };
      }

      const amountIn = amount.toString();
      const amountOut = calcOutNumber.toString();
      return { amountOut, amountIn };
    }

    case SwapKind.GIVEN_OUT: {
      const calcInNumber = calcSwapCCPoolUNSAFE(
        amount.toString(),
        adjustedOutReserves.toString(),
        adjustedInReserves.toString(),
        timeRemainingSeconds,
        +tParamSeconds,
        false // swapKind === SwapKind.GIVEN_IN (calculate output)
      );

      // We get back NaN when there are insufficient reserves
      if (!calcInNumber.toString()) {
        return {
          amountOut: amount.toString(),
          amountIn: "0",
          error: PrincipalPoolCalcSwapError.INSUFFICENT_RESERVES,
        };
      }

      const amountIn = calcInNumber.toString();
      const amountOut = amount.toString();
      return { amountOut, amountIn };
    }
    default:
      throw new UnreachableCaseError("NEVER" as never);
  }
}
