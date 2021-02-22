import {Tranche} from "../../typechain/Tranche";
import {Tranche__factory} from "../../typechain/factories/Tranche__factory";

import {ElfStub__factory} from "../../typechain/factories/ElfStub__factory";

import {YC} from "../../typechain/YC";
import {YC__factory} from "../../typechain/factories/YC__factory";
import {AToken} from "../../typechain/AToken";
import {AToken__factory} from "../../typechain/factories/AToken__factory";
import {AYVault} from "../../typechain/AYVault";
import {AYVault__factory} from "../../typechain/factories/AYVault__factory";
import {YVaultAssetProxy} from "../../typechain/YVaultAssetProxy";
import {YVaultAssetProxy__factory} from "../../typechain/factories/YVaultAssetProxy__factory"; 
import {YearnVault} from "../../typechain/YearnVault";
import {YearnVault__factory} from "../../typechain/factories/YearnVault__factory";
import {IWETH} from "../../typechain/IWETH";
import {IWETH__factory} from "../../typechain/factories/IWETH__factory";
import {IERC20} from "../../typechain/IERC20";
import {IERC20__factory} from "../../typechain/factories/IERC20__factory";
import {Signer} from "ethers";
import {ethers} from "hardhat";

export interface fixtureInterface {
  signer: Signer;
  usdc: AToken;
  yusdc: AYVault;
  yusdcElf: YVaultAssetProxy;
  tranche: Tranche;
  yc: YC;
}

export interface ethPoolMainnetInterface {
  signer: Signer;
  weth: IWETH;
  yweth: YearnVault;
  ywethAsset: YVaultAssetProxy;
}

export interface usdcPoolMainnetInterface {
  signer: Signer;
  usdc: IERC20;
  yusdc: YearnVault;
  yusdcAsset: YVaultAssetProxy;
}

const deployElfStub = async (signer: Signer) => {
  const deployer = new ElfStub__factory(signer);
  return await deployer.deploy();
};

const deployTranche = async (
  signer: Signer,
  elfAddress: string,
  lockDuration: number
) => {
  const deployer = new Tranche__factory(signer);
  return await deployer.deploy(elfAddress, lockDuration);
};

const deployUsdc = async (signer: Signer, owner: string) => {
  const deployer = new AToken__factory(signer);
  return await deployer.deploy(owner);
};

const deployYusdc = async (signer: Signer, usdcAddress: string) => {
  const deployer = new AYVault__factory(signer);
  return await deployer.deploy(usdcAddress);
};

const deployYasset = async (signer: Signer, yUnderlying: string, underlying: string, name: string, symbol: string) => {
  const yVaultDeployer = new YVaultAssetProxy__factory(signer);
  return await yVaultDeployer.deploy(yUnderlying, underlying, name, symbol);
}

export async function loadFixture() {
  const [signer] = await ethers.getSigners();
  const signerAddress = (await signer.getAddress()) as string;
  const usdc = await deployUsdc(signer, signerAddress);
  const yusdc = await deployYusdc(signer, usdc.address);

  const yusdcElf : YVaultAssetProxy = await deployYasset(signer, yusdc.address, usdc.address, "eyUSDC", "eyUSDC");
  const tranche = await deployTranche(signer, yusdcElf.address, 5000000);
  const ycAddress = await tranche.yc();
  const yc = YC__factory.connect(ycAddress, signer);

  return {
    signer,
    usdc,
    yusdc,
    yusdcElf,
    tranche,
    yc,
  };
}

export async function loadEthPoolMainnetFixture() {
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const ywethAddress = "0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7";
  const [signer] = await ethers.getSigners();

  const weth = IWETH__factory.connect(wethAddress, signer);
  const yweth = YearnVault__factory.connect(ywethAddress, signer);
  const ywethAsset = await deployYasset(signer, yweth.address, weth.address, "Element Yearn Wrapped Ether", "eyWETH");

  return {
    signer,
    weth,
    yweth,
    ywethAsset
  };
}

export async function loadUsdcPoolMainnetFixture() {
  const usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const yusdcAddress = "0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e";
  const [signer] = await ethers.getSigners();

  const usdc = IERC20__factory.connect(usdcAddress, signer);
  const yusdc = YearnVault__factory.connect(yusdcAddress, signer);
  const yusdcAsset = await deployYasset(signer, yusdc.address, usdc.address, "Element Yearn USDC", "eyUSDC");

  return {
    signer,
    usdc,
    yusdc,
    yusdcAsset
  };
}
