import "@nomiclabs/hardhat-waffle";
import "hardhat-typechain";

import {HardhatUserConfig, task} from "hardhat/config";
import {HardhatRuntimeEnvironment} from "hardhat/types";

// hre is provided on the global scope.  We cannot import it here or in any file we import since we
// cannot load the hre while doing configuration.
declare global {
  var hre: HardhatRuntimeEnvironment;
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: "0.8.0",
};

export default config;
