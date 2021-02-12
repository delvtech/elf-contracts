import "@nomiclabs/hardhat-waffle";
import "hardhat-typechain";

import {HardhatUserConfig} from "hardhat/config";

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [
      {
        version: "0.7.1",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10000
          }
         } 
      },
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10000
          }
         } 
      }
    ]
  },
};

export default config;
