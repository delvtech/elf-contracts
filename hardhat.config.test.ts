import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "tsconfig-paths/register";

import { HardhatUserConfig } from "hardhat/config";

import config from "./hardhat.config";

const testConfig: HardhatUserConfig = {
  ...config,
  networks: {
    ...config.networks,
    hardhat: {
      ...config?.networks?.hardhat,
      allowUnlimitedContractSize: true,
    },
  },
};

export default testConfig;
