import { ethers } from "hardhat";
import { BigNumberish, Signer } from "ethers";
import "module-alias/register";
import { DateString__factory } from "typechain/factories/DateString__factory";
import { IERC20__factory } from "typechain/factories/IERC20__factory";
import { InterestTokenFactory__factory } from "typechain/factories/InterestTokenFactory__factory";
import { InterestToken__factory } from "typechain/factories/InterestToken__factory";
import { IWETH__factory } from "typechain/factories/IWETH__factory";
import { IYearnVault__factory } from "typechain/factories/IYearnVault__factory";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { TestUserProxy__factory } from "typechain/factories/TestUserProxy__factory";
import { TestWrappedPosition__factory } from "typechain/factories/TestWrappedPosition__factory";
import { TestYVault__factory } from "typechain/factories/TestYVault__factory";
import { TrancheFactory__factory } from "typechain/factories/TrancheFactory__factory";
import { Tranche__factory } from "typechain/factories/Tranche__factory";
import { YVaultAssetProxy__factory } from "typechain/factories/YVaultAssetProxy__factory";
import { ZapTrancheHop__factory } from "typechain/factories/ZapTrancheHop__factory";
import { ZapYearnShares__factory } from "typechain/factories/ZapYearnShares__factory";
import { IERC20 } from "typechain/IERC20";
import { InterestToken } from "typechain/InterestToken";
import { IWETH } from "typechain/IWETH";
import { IYearnVault } from "typechain/IYearnVault";
import { TestERC20 } from "typechain/TestERC20";
import { TestUserProxy } from "typechain/TestUserProxy";
import { TestWrappedPosition } from "typechain/TestWrappedPosition";
import { TestYVault } from "typechain/TestYVault";
import { Tranche } from "typechain/Tranche";
import { TrancheFactory } from "typechain/TrancheFactory";
import { YVaultAssetProxy } from "typechain/YVaultAssetProxy";
import { ZapTrancheHop } from "typechain/ZapTrancheHop";
import { ZapYearnShares } from "typechain/ZapYearnShares";
import data from "../../artifacts/contracts/Tranche.sol/Tranche.json";
import { CompoundAssetProxy__factory } from "typechain/factories/CompoundAssetProxy__factory";
import { CTokenInterface__factory } from "typechain/factories/CTokenInterface__factory";
import { CompoundAssetProxy } from "typechain/CompoundAssetProxy";
import {
  ConvexAssetProxy,
  ConstructorParamsStruct,
} from "typechain/ConvexAssetProxy";
import { IConvexBooster } from "typechain/IConvexBooster";
import { IConvexBaseRewardPool } from "typechain/IConvexBaseRewardPool";
import { ISwapRouter } from "typechain/ISwapRouter";
import { I3CurvePoolDepositZap } from "typechain/I3CurvePoolDepositZap";
import { IConvexBooster__factory } from "typechain/factories/IConvexBooster__factory";
import { IConvexBaseRewardPool__factory } from "typechain/factories/IConvexBaseRewardPool__factory";
import { I3CurvePoolDepositZap__factory } from "./../../typechain/factories/I3CurvePoolDepositZap__factory";
import { ConvexAssetProxy__factory } from "typechain/factories/ConvexAssetProxy__factory";
import { ISwapRouter__factory } from "typechain/factories/ISwapRouter__factory";
import { CTokenInterface } from "typechain/CTokenInterface";

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

export interface CFixtureInterface {
  signer: Signer;
  position: CompoundAssetProxy;
  cusdc: CTokenInterface;
  usdc: IERC20;
  comp: IERC20;
  proxy: TestUserProxy;
}

export interface ConvexFixtureInterface {
  signer: Signer;
  position: ConvexAssetProxy;
  booster: IConvexBooster;
  rewardsContract: IConvexBaseRewardPool;
  curveZap: I3CurvePoolDepositZap;
  curveMetaPool: string;
  convexDepositToken: IERC20;
  lpToken: IERC20;
  router: ISwapRouter;
  usdc: IERC20;
  crv: IERC20;
  cvx: IERC20;
  proxy: TestUserProxy;
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

export interface TrancheTestFixtureWithBaseAsset {
  signer: Signer;
  usdc: TestERC20;
  positionStub: TestWrappedPosition;
  tranche: Tranche;
  interestToken: InterestToken;
  trancheFactory: TrancheFactory;
  bytecodehash: string;
}

export interface YearnShareZapInterface {
  sharesZapper: ZapYearnShares;
  signer: Signer;
  usdc: IERC20;
  yusdc: IYearnVault;
  position: YVaultAssetProxy;
  tranche: Tranche;
}

export interface TrancheHopInterface {
  trancheHop: ZapTrancheHop;
  signer: Signer;
  usdc: IERC20;
  yusdc: IYearnVault;
  position: YVaultAssetProxy;
  tranche1: Tranche;
  tranche2: Tranche;
  interestToken1: InterestToken;
  interestToken2: InterestToken;
}
const deployTestWrappedPosition = async (signer: Signer, address: string) => {
  const deployer = new TestWrappedPosition__factory(signer);
  return await deployer.deploy(address);
};

export const deployUsdc = async (signer: Signer, owner: string) => {
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
  const signerAddress = await signer.getAddress();
  return await yVaultDeployer.deploy(
    yUnderlying,
    underlying,
    name,
    symbol,
    signerAddress,
    signerAddress
  );
};

const deployCasset = async (
  signer: Signer,
  cToken: string,
  comptroller: string,
  compAddress: string,
  underlying: string,
  name: string,
  symbol: string,
  owner: string
) => {
  const cDeployer = new CompoundAssetProxy__factory(signer);
  return await cDeployer.deploy(
    cToken,
    comptroller,
    compAddress,
    underlying,
    name,
    symbol,
    owner
  );
};

const deployConvexAssetProxy = async (
  signer: Signer,
  curveZap: string,
  curveMetaPool: string,
  booster: string,
  rewardsContract: string,
  convexDepositToken: string,
  router: string,
  pid: BigNumberish,
  keeperFee: BigNumberish,
  crvSwapPath: string,
  cvxSwapPath: string,
  token: string,
  name: string,
  symbol: string,
  governance: string,
  pauser: string
) => {
  const convexDeployer = new ConvexAssetProxy__factory(signer);
  const constructorParams: ConstructorParamsStruct = {
    curveZap: curveZap,
    curveMetaPool: curveMetaPool,
    booster: booster,
    rewardsContract: rewardsContract,
    convexDepositToken: convexDepositToken,
    router: router,
    pid: pid,
    keeperFee: keeperFee,
  };
  return await convexDeployer.deploy(
    constructorParams,
    crvSwapPath,
    cvxSwapPath,
    token,
    name,
    symbol,
    governance,
    pauser
  );
};

const deployInterestTokenFactory = async (signer: Signer) => {
  const deployer = new InterestTokenFactory__factory(signer);
  return await deployer.deploy();
};

export const deployTrancheFactory = async (signer: Signer) => {
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

export async function loadFixtureWithBaseAsset(
  baseAsset: TestERC20,
  expiry: any
) {
  // The mainnet weth address won't work unless mainnet deployed
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const [signer] = await ethers.getSigners();
  const yusdc = await deployYusdc(signer, baseAsset.address, 6);
  const position: YVaultAssetProxy = await deployYasset(
    signer,
    yusdc.address,
    baseAsset.address,
    "eyUSDC",
    "eyUSDC"
  );

  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(expiry, position.address);
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
    usdc: baseAsset,
    yusdc,
    position,
    tranche,
    interestToken,
    proxy,
    trancheFactory,
  };
}

export async function loadFixture() {
  const [signer] = await ethers.getSigners();
  const signerAddress = (await signer.getAddress()) as string;
  const usdc = await deployUsdc(signer, signerAddress);
  return await loadFixtureWithBaseAsset(usdc, 1e10);
}

export async function loadCFixture(signer: Signer) {
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const owner = signer;
  const cusdcAddress = "0x39aa39c021dfbae8fac545936693ac917d5e7563";
  const usdcAddress = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
  const cusdc = CTokenInterface__factory.connect(cusdcAddress, owner);
  const usdc = IERC20__factory.connect(usdcAddress, owner);

  const comptrollerAddress = await cusdc.comptroller();
  const compAddress = "0xc00e94cb662c3520282e6f5717214004a7f26888";
  const comp = IERC20__factory.connect(compAddress, owner);

  const ownerAddress = await signer.getAddress();

  // deploy casset
  const position: CompoundAssetProxy = await deployCasset(
    owner,
    cusdcAddress,
    comptrollerAddress,
    compAddress,
    usdcAddress,
    "cusdc",
    "element cusdc",
    ownerAddress
  );

  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(owner);
  await trancheFactory.deployTranche(1e10, position.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, owner);

  const interestTokenAddress = await tranche.interestToken();
  const interestToken = InterestToken__factory.connect(
    interestTokenAddress,
    owner
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

  return { signer, position, cusdc, usdc, comp, proxy };
}

export async function loadConvexFixture(
  signer: Signer
): Promise<ConvexFixtureInterface> {
  // Some addresses specific to LUSD3CRV pool
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const owner = signer;
  const usdcAddress = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
  const crvAddress = "0xD533a949740bb3306d119CC777fa900bA034cd52";
  const cvxAddress = "0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B";
  const boosterAddress = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31";
  const rewardsContractAddress = "0x2ad92A7aE036a038ff02B96c88de868ddf3f8190";
  const pool3CrvDepositZapAddress =
    "0xA79828DF1850E8a3A3064576f380D90aECDD3359";
  // Metapool for LUSD3CRV, also the LP token address
  const curveMetaPool = "0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA";
  const cvxLusd3CRV = "0xFB9B2f06FDb404Fd3E2278E9A9edc8f252F273d0";
  // Uniswap V3 router address
  const routerAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564";
  // Pool ID for LUSD-3CRV pool
  const pid = 33;
  // Keeper fee is 5%
  const keeperFee = 50;
  // multi-hops are [TokenA, fee, TokenB, fee, TokenC, ... TokenOut]
  // Jump from CRV to WETH to USDC
  // Note: 10000 = 1% pool fee
  const crvSwapPath = ethers.utils.solidityPack(
    ["address", "uint24", "address", "uint24", "address"],
    [crvAddress, 10000, wethAddress, 500, usdcAddress]
  );
  const cvxSwapPath = ethers.utils.solidityPack(
    ["address", "uint24", "address", "uint24", "address"],
    [cvxAddress, 10000, wethAddress, 500, usdcAddress]
  );

  const usdc = IERC20__factory.connect(usdcAddress, owner);
  const crv = IERC20__factory.connect(crvAddress, owner);
  const cvx = IERC20__factory.connect(cvxAddress, owner);
  const booster = IConvexBooster__factory.connect(boosterAddress, owner);
  const rewardsContract = IConvexBaseRewardPool__factory.connect(
    rewardsContractAddress,
    owner
  );
  const curveZap = I3CurvePoolDepositZap__factory.connect(
    pool3CrvDepositZapAddress,
    owner
  );
  const convexDepositToken = IERC20__factory.connect(cvxLusd3CRV, owner);
  const lpToken = IERC20__factory.connect(curveMetaPool, owner);
  const router = ISwapRouter__factory.connect(routerAddress, owner);

  const ownerAddress = await signer.getAddress();

  const position: ConvexAssetProxy = await deployConvexAssetProxy(
    owner,
    pool3CrvDepositZapAddress,
    curveMetaPool,
    boosterAddress,
    rewardsContractAddress,
    cvxLusd3CRV,
    routerAddress,
    pid,
    keeperFee,
    crvSwapPath,
    cvxSwapPath,
    curveMetaPool,
    "proxyLusd3CRV",
    "epLusd3Crv",
    ownerAddress,
    ownerAddress
  );

  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(owner);
  await trancheFactory.deployTranche(1e10, position.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, owner);

  const interestTokenAddress = await tranche.interestToken();
  const interestToken = InterestToken__factory.connect(
    interestTokenAddress,
    owner
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
    position,
    booster,
    rewardsContract,
    curveZap,
    curveMetaPool,
    convexDepositToken,
    lpToken,
    router,
    usdc,
    crv,
    cvx,
    proxy,
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

export async function loadTestTrancheFixtureWithBaseAsset(
  baseAsset: TestERC20,
  expiration: any
) {
  const [signer] = await ethers.getSigners();
  const positionStub: TestWrappedPosition = await deployTestWrappedPosition(
    signer,
    baseAsset.address
  );
  // deploy and fetch tranche contract
  const trancheFactory = await deployTrancheFactory(signer);
  await trancheFactory.deployTranche(expiration, positionStub.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress = events[0] && events[0].args && events[0].args[0];
  const tranche = Tranche__factory.connect(trancheAddress, signer);

  const interestTokenAddress = await tranche.interestToken();
  const interestToken = InterestToken__factory.connect(
    interestTokenAddress,
    signer
  );

  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );

  return {
    signer,
    usdc: baseAsset,
    positionStub,
    tranche,
    interestToken,
    trancheFactory,
    bytecodehash,
  };
}

export async function loadTestTrancheFixture() {
  const [signer] = await ethers.getSigners();
  const testTokenDeployer = new TestERC20__factory(signer);
  const usdc = await testTokenDeployer.deploy("test token", "TEST", 6);
  const t = await loadTestTrancheFixtureWithBaseAsset(usdc, 1e10);
  return {
    signer: t.signer,
    usdc: t.usdc,
    positionStub: t.positionStub,
    tranche: t.tranche,
    interestToken: t.interestToken,
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

export async function loadTrancheHopFixture(toAuth: string) {
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
  await trancheFactory.deployTranche(2e10, position.address);
  const eventFilter = trancheFactory.filters.TrancheCreated(null, null, null);
  const events = await trancheFactory.queryFilter(eventFilter);
  const trancheAddress1 = events[0] && events[0].args && events[0].args[0];
  const trancheAddress2 = events[1] && events[1].args && events[1].args[0];

  const tranche1 = Tranche__factory.connect(trancheAddress1, signer);
  const tranche2 = Tranche__factory.connect(trancheAddress2, signer);

  const interestTokenAddress1 = await tranche1.interestToken();
  const interestToken1 = InterestToken__factory.connect(
    interestTokenAddress1,
    signer
  );
  const interestTokenAddress2 = await tranche2.interestToken();
  const interestToken2 = InterestToken__factory.connect(
    interestTokenAddress2,
    signer
  );
  // Setup the proxy
  const bytecodehash = ethers.utils.solidityKeccak256(
    ["bytes"],
    [data.bytecode]
  );

  const deployer = new ZapTrancheHop__factory(signer);
  const trancheHop = await deployer.deploy(
    trancheFactory.address,
    bytecodehash
  );
  await trancheHop.connect(signer).authorize(toAuth);
  await trancheHop.connect(signer).setOwner(toAuth);

  return {
    trancheHop,
    signer,
    usdc,
    yusdc,
    position,
    tranche1,
    tranche2,
    interestToken1,
    interestToken2,
  };
}
