import { MockProvider } from "ethereum-waffle";

export const advanceTime = async (provider: MockProvider, time: number) => {
  await provider.send("evm_increaseTime", [time]);
  await provider.send("evm_mine", []);
};

export const advanceBlock = async (provider: MockProvider) => {
  await provider.send("evm_mine", []);
};

export const getCurrentTimestamp = async (provider: MockProvider) => {
  const blockNumber = await provider.getBlockNumber();
  const block = await provider.getBlock(blockNumber);
  return block.timestamp;
};

export const ONE_MINUTE_IN_SECONDS = 60;
export const ONE_HOUR_IN_SECONDS = 60 * ONE_MINUTE_IN_SECONDS;
export const ONE_DAY_IN_SECONDS = 24 * ONE_HOUR_IN_SECONDS;
export const ONE_WEEK_IN_SECONDS = 7 * ONE_DAY_IN_SECONDS;
export const THIRTY_DAYS_IN_SECONDS = 30 * ONE_DAY_IN_SECONDS;
export const SIX_MONTHS_IN_SECONDS = 26 * ONE_WEEK_IN_SECONDS;

export const ONE_MINUTE_IN_MILLISECONDS = 1000 * ONE_MINUTE_IN_SECONDS;
export const ONE_HOUR_IN_MILLISECONDS = 60 * ONE_MINUTE_IN_MILLISECONDS;
export const ONE_DAY_IN_MILLISECONDS = 24 * ONE_HOUR_IN_MILLISECONDS;
export const ONE_WEEK_IN_MILLISECONDS = 7 * ONE_DAY_IN_MILLISECONDS;
export const ONE_YEAR_IN_MILLISECONDS = 365 * ONE_DAY_IN_MILLISECONDS;
export const THIRTY_DAYS_IN_MILLISECONDS = 30 * ONE_DAY_IN_MILLISECONDS;
