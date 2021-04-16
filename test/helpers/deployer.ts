import "module-alias/register";

import { Signer } from "ethers";
import { ethers } from "hardhat";
import { TestERC20 } from "typechain/TestERC20";
import { TestYVault } from "typechain/TestYVault";
import { TestWrappedPosition } from "typechain/TestWrappedPosition";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { TestYVault__factory } from "typechain/factories/TestYVault__factory";
import { TestWrappedPosition__factory } from "typechain/factories/TestWrappedPosition__factory";
import { IERC20__factory } from "typechain/factories/IERC20__factory";
import { IWETH__factory } from "typechain/factories/IWETH__factory";
import { IYearnVault__factory } from "typechain/factories/IYearnVault__factory";
import { Tranche__factory } from "typechain/factories/Tranche__factory";
import { TrancheFactory__factory } from "typechain/factories/TrancheFactory__factory";
import { TestUserProxy__factory } from "typechain/factories/TestUserProxy__factory";
import { InterestToken__factory } from "typechain/factories/InterestToken__factory";
import { InterestTokenFactory__factory } from "typechain/factories/InterestTokenFactory__factory";
import { YVaultAssetProxy__factory } from "typechain/factories/YVaultAssetProxy__factory";
import { IERC20 } from "typechain/IERC20";
import { IWETH } from "typechain/IWETH";
import { IYearnVault } from "typechain/IYearnVault";
import { Tranche } from "typechain/Tranche";
import { TrancheFactory } from "typechain/TrancheFactory";
import { TestUserProxy } from "typechain/TestUserProxy";
import { InterestToken } from "typechain/InterestToken";
import { YVaultAssetProxy } from "typechain/YVaultAssetProxy";

import data from "../../artifacts/contracts/Tranche.sol/Tranche.json";

export interface FixtureInterface {
  signer: Signer;
  erc20: TestERC20;
  yvault: TestYVault;
  position: YVaultAssetProxy;
  tranche: Tranche;
  interestToken: InterestToken;
  proxy: TestUserProxy;
  trancheFactory: TrancheFactory;
}

export interface EthPoolMainnetInterface {
  signer: Signer;
  weth: IWETH;
  yweth: IYearnVault;
  position: YVaultAssetProxy;
  tranche: Tranche;
  proxy: TestUserProxy;
}

export interface UsdcPoolMainnetInterface {
  signer: Signer;
  usdc: IERC20;
  yusdc: IYearnVault;
  position: YVaultAssetProxy;
  tranche: Tranche;
  proxy: TestUserProxy;
}

export interface TrancheTestFixture {
  signer: Signer;
  usdc: TestERC20;
  positionStub: TestWrappedPosition;
  tranche: Tranche;
  interestToken: InterestToken;
}

const deployTestWrappedPosition = async (signer: Signer, address: string) => {
  const deployer = new TestWrappedPosition__factory(signer);
  return await deployer.deploy(address);
};

const deployErc20 = async (signer: Signer, owner: string) => {
  const deployer = new TestERC20__factory(signer);
  return await deployer.deploy(owner, "tTKN", 18);
};

const deployYvault = async (signer: Signer, usdcAddress: string) => {
  const deployer = new TestYVault__factory(signer);
  return await deployer.deploy(usdcAddress);
};

const deployYasset = async (
  signer: Signer,
  yUnderlying: string,
  underlying: string,
  name: string,
  symbol: string
) => {
  const yVaultDeployer = new YVaultAssetProxy__factory(signer);
  return await yVaultDeployer.deploy(yUnderlying, underlying, name, symbol);
};

const deployInterestTokenFactory = async (signer: Signer) => {
  const deployer = new InterestTokenFactory__factory(signer);
  return await deployer.deploy();
};

const deployTrancheFactory = async (signer: Signer) => {
  const interestTokenFactory = await deployInterestTokenFactory(signer);
  const deployer = new TrancheFactory__factory(signer);
  const deployTx = await deployer.deploy(interestTokenFactory.address);
  return deployTx;
};

export async function loadFixture() {
  // The mainnet weth address won't work unless mainnet deployed
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const [signer] = await ethers.getSigners();
  const signerAddress = (await signer.getAddress()) as string;
  const erc20 = await deployErc20(signer, signerAddress);
  const yvault = await deployYvault(signer, erc20.address);
  const decimals = await yvault.decimals();
  const position: YVaultAssetProxy = await deployYasset(
    signer,
    yvault.address,
    erc20.address,
    "eyTKN",
    "eyTKN"
  );

  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(1e10, position.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);

  const interestTokenAddress = await tranche.interestToken();
  const interestToken = InterestToken__factory.connect(
    interestTokenAddress,
    signer
  );

  // Setup the proxy
  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );
  const proxyFactory = new TestUserProxy__factory(signer);
  const proxy = await proxyFactory.deploy(
    wethAddress,
    trancheFactory.address,
    bytecodehash
  );
  return {
    signer,
    erc20,
    yvault,
    position,
    tranche,
    interestToken,
    proxy,
    trancheFactory,
  };
}

export async function loadEthPoolMainnetFixture() {
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const ywethAddress = "0xac333895ce1A73875CF7B4Ecdc5A743C12f3d82B";
  const [signer] = await ethers.getSigners();

  const weth = IWETH__factory.connect(wethAddress, signer);
  const yweth = IYearnVault__factory.connect(ywethAddress, signer);
  const position = await deployYasset(
    signer,
    yweth.address,
    weth.address,
    "Element Yearn Wrapped Ether",
    "eyWETH"
  );

  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(1e10, position.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);
  // Setup the proxy
  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );
  const proxyFactory = new TestUserProxy__factory(signer);
  const proxy = await proxyFactory.deploy(
    wethAddress,
    trancheFactory.address,
    bytecodehash
  );
  return {
    signer,
    weth,
    yweth,
    position,
    tranche,
    proxy,
  };
}

export async function loadUsdcPoolMainnetFixture() {
  const usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const yusdcAddress = "0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9";
  const [signer] = await ethers.getSigners();

  const usdc = IERC20__factory.connect(usdcAddress, signer);
  const yusdc = IYearnVault__factory.connect(yusdcAddress, signer);
  const position = await deployYasset(
    signer,
    yusdc.address,
    usdc.address,
    "Element Yearn USDC",
    "eyUSDC"
  );
  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(1e10, position.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);
  // Setup the proxy
  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );
  const proxyFactory = new TestUserProxy__factory(signer);
  const proxy = await proxyFactory.deploy(
    usdcAddress,
    trancheFactory.address,
    bytecodehash
  );

  return {
    signer,
    usdc,
    yusdc,
    position,
    tranche,
    proxy,
  };
}
export async function loadTestTrancheFixture() {
  const [signer] = await ethers.getSigners();
  const testTokenDeployer = new TestERC20__factory(signer);
  const usdc = await testTokenDeployer.deploy("test token", "TEST", 18);

  const positionStub: TestWrappedPosition = await deployTestWrappedPosition(
    signer,
    usdc.address
  );
  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(1e10, positionStub.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);

  const interestTokenAddress = await tranche.interestToken();
  const interestToken = InterestToken__factory.connect(
    interestTokenAddress,
    signer
  );

  return {
    signer,
    usdc,
    positionStub,
    tranche,
    interestToken,
  };
}
