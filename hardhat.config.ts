import "@nomiclabs/hardhat-waffle";
import "hardhat-typechain";

import {HardhatUserConfig} from "hardhat/config";

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: "0.8.0",
};

export default config;
