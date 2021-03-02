import { MockProvider } from "ethereum-waffle";

const snapshotIdStack: number[] = [];
export const createSnapshot = async (provider: MockProvider) => {
  const id = await provider.send("evm_snapshot", []);
  snapshotIdStack.push(id);
};

export const restoreSnapshot = async (provider: MockProvider) => {
  const id = snapshotIdStack.pop();
  try {
    await provider.send("evm_revert", [id]);
  } catch (ex) {
    throw new Error(`Snapshot with id #${id} failed to revert`);
  }
};
