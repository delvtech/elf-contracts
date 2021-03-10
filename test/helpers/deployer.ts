import "module-alias/register";

import { Tranche } from "../../typechain/Tranche";
import { Tranche__factory } from "../../typechain/factories/Tranche__factory";
import { ElfStub__factory } from "../../typechain/factories/ElfStub__factory";
import { YC } from "../../typechain/YC";
import { YC__factory } from "../../typechain/factories/YC__factory";
import { AToken } from "../../typechain/AToken";
import { AToken__factory } from "../../typechain/factories/AToken__factory";
import { AYVault } from "../../typechain/AYVault";
import { AYVault__factory } from "../../typechain/factories/AYVault__factory";
import { YVaultAssetProxy } from "../../typechain/YVaultAssetProxy";
import { YVaultAssetProxy__factory } from "../../typechain/factories/YVaultAssetProxy__factory";
import { IYearnVault } from "../../typechain/IYearnVault";
import { IYearnVault__factory } from "../../typechain/factories/IYearnVault__factory";
import { IWETH } from "../../typechain/IWETH";
import { IWETH__factory } from "../../typechain/factories/IWETH__factory";
import { IERC20 } from "../../typechain/IERC20";
import { IERC20__factory } from "../../typechain/factories/IERC20__factory";
import { TestERC20 } from "../../typechain/TestERC20";
import { TestERC20__factory } from "../../typechain/factories/TestERC20__factory";
import { UserProxyTest } from "../../typechain/UserProxyTest";
import { UserProxyTest__factory } from "../../typechain/factories/UserProxyTest__factory";
import { TrancheFactory } from "../../typechain/TrancheFactory";
import { TrancheFactory__factory } from "../../typechain/factories/TrancheFactory__factory";
import { YCFactory__factory } from "../../typechain/factories/YCFactory__factory";
import data from "../../artifacts/contracts/Tranche.sol/Tranche.json";
import { Signer } from "ethers";
import { ethers } from "hardhat";
import { ElfStub } from "../../typechain/ElfStub";

export interface FixtureInterface {
  signer: Signer;
  usdc: AToken;
  yusdc: AYVault;
  elf: YVaultAssetProxy;
  tranche: Tranche;
  yc: YC;
  proxy: UserProxyTest;
  trancheFactory: TrancheFactory;
}

export interface EthPoolMainnetInterface {
  signer: Signer;
  weth: IWETH;
  yweth: IYearnVault;
  elf: YVaultAssetProxy;
  tranche: Tranche;
  proxy: UserProxyTest;
}

export interface UsdcPoolMainnetInterface {
  signer: Signer;
  usdc: IERC20;
  yusdc: IYearnVault;
  elf: YVaultAssetProxy;
  tranche: Tranche;
  proxy: UserProxyTest;
}

export interface TrancheTestFixture {
  signer: Signer;
  usdc: TestERC20;
  elfStub: ElfStub;
  tranche: Tranche;
  yc: YC;
}

const deployElfStub = async (signer: Signer, address: string) => {
  const deployer = new ElfStub__factory(signer);
  return await deployer.deploy(address);
};

const deployUsdc = async (signer: Signer, owner: string) => {
  const deployer = new AToken__factory(signer);
  return await deployer.deploy(owner);
};

const deployYusdc = async (signer: Signer, usdcAddress: string) => {
  const deployer = new AYVault__factory(signer);
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

const deployYCFactory = async (signer: Signer) => {
  const deployer = new YCFactory__factory(signer);
  return await deployer.deploy();
};

const deployTrancheFactory = async (signer: Signer) => {
  const ycFactory = await deployYCFactory(signer);
  const deployer = new TrancheFactory__factory(signer);
  return await deployer.deploy(ycFactory.address);
};

export async function loadFixture() {
  // The mainnet weth address won't work unless mainnet deployed
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const [signer] = await ethers.getSigners();
  const signerAddress = (await signer.getAddress()) as string;
  const usdc = await deployUsdc(signer, signerAddress);
  const yusdc = await deployYusdc(signer, usdc.address);

  const elf: YVaultAssetProxy = await deployYasset(
    signer,
    yusdc.address,
    usdc.address,
    "eyUSDC",
    "eyUSDC"
  );

  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(1e10, elf.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);

  const ycAddress = await tranche.yc();
  const yc = YC__factory.connect(ycAddress, signer);

  // Setup the proxy
  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );
  const proxyFactory = new UserProxyTest__factory(signer);
  const proxy = await proxyFactory.deploy(
    wethAddress,
    trancheFactory.address,
    bytecodehash
  );
  return {
    signer,
    usdc,
    yusdc,
    elf,
    tranche,
    yc,
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
  const elf = await deployYasset(
    signer,
    yweth.address,
    weth.address,
    "Element Yearn Wrapped Ether",
    "eyWETH"
  );

  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(1e10, elf.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);
  // Setup the proxy
  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );
  const proxyFactory = new UserProxyTest__factory(signer);
  const proxy = await proxyFactory.deploy(
    wethAddress,
    trancheFactory.address,
    bytecodehash
  );
  return {
    signer,
    weth,
    yweth,
    elf,
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
  const elf = await deployYasset(
    signer,
    yusdc.address,
    usdc.address,
    "Element Yearn USDC",
    "eyUSDC"
  );
  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(1e10, elf.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);
  // Setup the proxy
  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );
  const proxyFactory = new UserProxyTest__factory(signer);
  const proxy = await proxyFactory.deploy(
    usdcAddress,
    trancheFactory.address,
    bytecodehash
  );

  return {
    signer,
    usdc,
    yusdc,
    elf,
    tranche,
    proxy,
  };
}

export async function loadTestTrancheFixture() {
  const [signer] = await ethers.getSigners();
  const testTokenDeployer = new TestERC20__factory(signer);
  const usdc = await testTokenDeployer.deploy("test token", "TEST", 18);

  const elfStub: ElfStub = await deployElfStub(signer, usdc.address);
  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(1e10, elfStub.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);

  const ycAddress = await tranche.yc();
  const yc = YC__factory.connect(ycAddress, signer);

  return {
    signer,
    usdc,
    elfStub,
    tranche,
    yc,
  };
}
