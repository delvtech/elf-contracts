import "@nomiclabs/hardhat-waffle";
import "hardhat-typechain";

import {HardhatUserConfig} from "hardhat/config";

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url:
          "https://eth-mainnet.alchemyapi.io/v2/kwjMP-X-Vajdk1ItCfU-56Uaq1wwhamK",
        blockNumber: 11853372,
      },
      accounts: {
        accountsBalance: "100000000000000000000000", // 100000 ETH
        count: 4,
      },
    },
  },
  solidity: "0.8.0",
};

export default config;
