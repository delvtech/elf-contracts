import { providers } from "ethers";
// An interface to allow us to access the ethers log return
export interface LogData {
  event: string;

  // TODO: figure out what this is.
  data: unknown;
  args: Array<any>;
}

// A partially extended interface for the post mining transaction receipt
export interface PostExecutionTransactionReceipt
  extends providers.TransactionReceipt {
  events: LogData[];
}

export async function mineTx(
  tx: Promise<providers.TransactionResponse>
): Promise<PostExecutionTransactionReceipt> {
  return (await tx).wait() as Promise<PostExecutionTransactionReceipt>;
}
