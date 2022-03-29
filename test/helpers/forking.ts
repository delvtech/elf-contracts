import { network } from "hardhat";

export const setBlock = async (block: number) => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_MAINNET_API_KEY}`,
          blockNumber: block,
        },
      },
    ],
  });
};
