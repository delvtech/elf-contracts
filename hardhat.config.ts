import "@nomiclabs/hardhat-waffle";
import "hardhat-typechain";
import "hardhat-gas-reporter";
import "solidity-coverage";

import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [
      {
        version: "0.7.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10000,
          },
        },
      },
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: false,
            runs: 7500,
          },
        },
      },
    ],
    overrides: {
      "contracts/vault/Vault.sol": {
        version: "0.7.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 400,
          },
        },
      },
    },
  },
  mocha: { timeout: 0 },
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
};

export default config;
