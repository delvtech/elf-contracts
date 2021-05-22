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
import { ZapYearnShares__factory } from "typechain/factories/ZapYearnShares__factory";
import { ZapYearnShares } from "typechain/ZapYearnShares";
import { ZapSteth } from "typechain/ZapSteth";
import { ZapSteth__factory } from "typechain/factories/ZapSteth__factory";
import { ICurveFi } from "typechain/ICurveFi";
import { ICurveFi__factory } from "typechain/factories/ICurveFi__factory";
import { IERC20 } from "typechain/IERC20";
import { IWETH } from "typechain/IWETH";
import { IYearnVault } from "typechain/IYearnVault";
import { Tranche } from "typechain/Tranche";
import { TrancheFactory } from "typechain/TrancheFactory";
import { TestUserProxy } from "typechain/TestUserProxy";
import { InterestToken } from "typechain/InterestToken";
import { YVaultAssetProxy } from "typechain/YVaultAssetProxy";
import { DateString__factory } from "typechain/factories/DateString__factory";

import data from "../../artifacts/contracts/Tranche.sol/Tranche.json";

export interface FixtureInterface {
  signer: Signer;
  usdc: TestERC20;
  yusdc: TestYVault;
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

export interface YearnShareZapInterface {
  sharesZapper: ZapYearnShares;
  signer: Signer;
  usdc: IERC20;
  yusdc: IYearnVault;
  position: YVaultAssetProxy;
  tranche: Tranche;
}

export interface StethPoolMainnetInterface {
  stableSwap: ICurveFi;
  curveLp: IERC20;
  steth: IERC20;
  yvstecrv: IYearnVault;
  position: YVaultAssetProxy;
  tranche: Tranche;
  zapper: ZapSteth;
  interestToken: InterestToken;
}

const deployTestWrappedPosition = async (signer: Signer, address: string) => {
  const deployer = new TestWrappedPosition__factory(signer);
  return await deployer.deploy(address);
};

const deployUsdc = async (signer: Signer, owner: string) => {
  const deployer = new TestERC20__factory(signer);
  return await deployer.deploy(owner, "tUSDC", 6);
};

const deployYusdc = async (
  signer: Signer,
  usdcAddress: string,
  decimals: number
) => {
  const deployer = new TestYVault__factory(signer);
  return await deployer.deploy(usdcAddress, decimals);
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
  const dateLibFactory = new DateString__factory(signer);
  const dateLib = await dateLibFactory.deploy();
  const deployTx = await deployer.deploy(
    interestTokenFactory.address,
    dateLib.address
  );
  return deployTx;
};

export async function loadFixture() {
  // The mainnet weth address won't work unless mainnet deployed
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const [signer] = await ethers.getSigners();
  const signerAddress = (await signer.getAddress()) as string;
  const usdc = await deployUsdc(signer, signerAddress);
  const yusdc = await deployYusdc(signer, usdc.address, 6);
  const position: YVaultAssetProxy = await deployYasset(
    signer,
    yusdc.address,
    usdc.address,
    "eyUSDC",
    "eyUSDC"
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
    usdc,
    yusdc,
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
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
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
    wethAddress,
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
  const usdc = await testTokenDeployer.deploy("test token", "TEST", 6);

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
export async function loadYearnShareZapFixture() {
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

  const deployer = new ZapYearnShares__factory(signer);
  const sharesZapper = await deployer.deploy(
    trancheFactory.address,
    bytecodehash
  );

  return {
    sharesZapper,
    signer,
    usdc,
    yusdc,
    position,
    tranche,
  };
}
export async function loadStethPoolMainnetFixture(toAuth: string) {
  const stETHaddress = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";
  const yvstecrvAddress = "0xdCD90C7f6324cfa40d7169ef80b12031770B4325";
  const stethStableSwap = "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022";
  const lpTokenAddress = "0x06325440D014e39736583c165C2963BA99fAf14E";
  const [signer] = await ethers.getSigners();

  const stableSwap = ICurveFi__factory.connect(stethStableSwap, signer);

  const curveLp = IERC20__factory.connect(lpTokenAddress, signer);

  const steth = IERC20__factory.connect(stETHaddress, signer);
  const yvstecrv = IYearnVault__factory.connect(yvstecrvAddress, signer);
  const deployer = new ZapSteth__factory(signer);
  const position = await deployYasset(
    signer,
    yvstecrv.address,
    "0x06325440D014e39736583c165C2963BA99fAf14E",
    "Element Yearn stETH",
    "yvsteCRV"
  );
  // deploy tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(1e10, position.address);

  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);

  // fetch tranche contract
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);
  // fetch yield token
  const interestTokenAddress = await tranche.interestToken();
  const interestToken = InterestToken__factory.connect(
    interestTokenAddress,
    signer
  );

  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );
  // Setup the zapper
  const zapper = await deployer.deploy(trancheFactory.address, bytecodehash);
  await zapper.connect(signer).authorize(toAuth);

  return {
    stableSwap,
    curveLp,
    steth,
    yvstecrv,
    position,
    tranche,
    zapper,
    interestToken,
  };
}
