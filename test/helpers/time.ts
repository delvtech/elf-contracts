import {MockProvider} from "ethereum-waffle";

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
