import { defaultAbiCoder, parseUnits } from "ethers/lib/utils";
import { BigNumber } from "ethers";

const ZeroBigNumber = BigNumber.from(0);

enum WeightedPoolExitKind {
  EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
  EXACT_BPT_IN_FOR_TOKENS_OUT,
  BPT_IN_FOR_EXACT_TOKENS_OUT,
}

enum WeightedPoolJoinKind {
  INIT,
  EXACT_TOKENS_IN_FOR_BPT_OUT,
  TOKEN_IN_FOR_EXACT_BPT_OUT,
}

export async function ccPoolExitRequest(
  tokens: string[],
  minAmountOut: string
) {
  const parseToken = (value: string) => parseUnits(value, 18);

  const minAmountsOut = [parseToken(minAmountOut), parseToken(minAmountOut)];
  // Balancer V2 vault allows userData as a way to pass props through to pool contracts.  In our
  // case we need to pass the minAmountsOut.
  const userData = defaultAbiCoder.encode(["uint256[]"], [minAmountsOut]);

  // return the exit request
  return {
    assets: tokens,
    minAmountsOut,
    userData,
    toInternalBalance: false,
  };
}

export async function ccPoolJoinRequest(tokens: string[], maxAmountIn: string) {
  const parseToken = (value: string) => parseUnits(value, 18);

  // just do same amounts for each, balancer will figure out how much of each you need.
  const maxAmountsIn = [parseToken(maxAmountIn), parseToken(maxAmountIn)];
  // Balancer V2 vault allows userData as a way to pass props through to pool contracts.  In our
  // case we need to pass the maxAmountsIn.
  const userData = defaultAbiCoder.encode(["uint256[]"], [maxAmountsIn]);
  // return the join request
  return {
    assets: tokens,
    maxAmountsIn,
    userData,
    fromInternalBalance: false,
  };
}

export async function weightedPoolExitRequest(
  decimals: number,
  tokens: string[],
  amounts: string[],
  maxBPTIn: BigNumber
) {
  const parseToken = (value: string) => parseUnits(value, decimals);
  // Balancer V2 vault allows userData as a way to pass props through to pool contracts.
  const minAmountsOut = [parseToken(amounts[0]), parseToken(amounts[1])];
  const userData = defaultAbiCoder.encode(
    ["uint8", "uint256"],
    [WeightedPoolExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, maxBPTIn]
  );

  return {
    assets: tokens,
    minAmountsOut,
    userData,
    toInternalBalance: false,
  };
}

export async function weightedPoolJoinRequest(
  decimals: number,
  tokens: string[],
  amounts: string[]
) {
  const parseToken = (value: string) => parseUnits(value, decimals);
  // Balancer V2 vault allows userData as a way to pass props through to pool contracts.  In this
  // case we need to pass the joinKind, maxAmountsIn and minBPTOut.
  const maxAmountsIn = [parseToken(amounts[0]), parseToken(amounts[1])];

  const userData = defaultAbiCoder.encode(
    ["uint8", "uint256[]", "uint256"],
    [
      WeightedPoolJoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
      maxAmountsIn,
      ZeroBigNumber,
    ]
  );
  // return the join request
  return {
    assets: tokens,
    maxAmountsIn,
    userData,
    fromInternalBalance: false,
  };
}
