import { network } from "hardhat";

export const setBlock = async (block: number) => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl:
            "https://eth-mainnet.alchemyapi.io/v2/kwjMP-X-Vajdk1ItCfU-56Uaq1wwhamK",
          blockNumber: block,
        },
      },
    ],
  });
};
