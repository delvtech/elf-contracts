import {Elf} from "../../typechain/Elf";
import {ElfStub} from "../../typechain/ElfStub";
import {Tranche} from "../../typechain/Tranche";
import {YC} from "../../typechain/YC";
import {ElfFactory} from "../../typechain/ElfFactory";
import {AToken} from "../../typechain/AToken";
import {AYVault} from "../../typechain/AYVault";
import {YVaultAssetProxy} from "../../typechain/YVaultAssetProxy";
import {YearnVault} from "../../typechain/YearnVault";

import {YearnVault__factory} from "../../typechain/factories/YearnVault__factory";
import {Elf__factory} from "../../typechain/factories/Elf__factory";
import {YC__factory} from "../../typechain/factories/YC__factory";

import {Signer} from "ethers";
import {ethers} from "hardhat";

export interface fixtureInterface {
  signer: Signer;
  elfFactory: ElfFactory;
  usdc: AToken;
  yusdc: AYVault;
  yusdcAsset: YVaultAssetProxy;
  yusdcAssetVault: YearnVault;
  elf: Elf;
  elfStub: ElfStub;
  tranche: Tranche;
  yc: YC;
}

const deployElfFactory = async (signer: Signer) => {
  const deployer = await ethers.getContractFactory("ElfFactory", signer);
  return (await deployer.deploy()) as ElfFactory;
};

const deployElfStub = async (signer: Signer) => {
  const deployer = await ethers.getContractFactory("ElfStub", signer);
  return (await deployer.deploy()) as ElfStub;
};

const deployTranche = async (
  signer: Signer,
  elfAddress: string,
  lockDuration: number
) => {
  const deployer = await ethers.getContractFactory("Tranche", signer);
  return (await deployer.deploy(elfAddress, lockDuration)) as Tranche;
};

const deployUsdc = async (signer: Signer, owner: string) => {
  const deployer = await ethers.getContractFactory("AToken", signer);
  return (await deployer.deploy(owner)) as AToken;
};

const deployYusdc = async (signer: Signer, usdcAddress: string) => {
  const deployer = await ethers.getContractFactory("AYVault", signer);
  return (await deployer.deploy(usdcAddress)) as AYVault;
};

const deployYusdcAsset = async (
  signer: Signer,
  yusdcAddress: string,
  usdcAddress: string
) => {
  const deployer = await ethers.getContractFactory("YVaultAssetProxy", signer);
  return (await deployer.deploy(yusdcAddress, usdcAddress)) as YVaultAssetProxy;
};

export async function loadFixture() {
  const [signer] = await ethers.getSigners();
  const signerAddress = (await signer.getAddress()) as string;
  const elfStub = (await deployElfStub(signer)) as ElfStub;
  const tranche = (await deployTranche(
    signer,
    elfStub.address,
    5000000
  )) as Tranche;
  const elfFactory = (await deployElfFactory(signer)) as ElfFactory;
  const usdc = (await deployUsdc(signer, signerAddress)) as AToken;
  const yusdc = (await deployYusdc(signer, usdc.address)) as AYVault;
  const yusdcAsset = (await deployYusdcAsset(
    signer,
    yusdc.address,
    usdc.address
  )) as YVaultAssetProxy;

  const vaultAddress = await yusdcAsset.vault();
  const yusdcAssetVault = YearnVault__factory.connect(vaultAddress, signer);

  const ycAddress = await tranche.yc();
  const yc = YC__factory.connect(ycAddress, signer);

  await elfFactory.newPool(usdc.address, yusdcAsset.address);

  const filter = await elfFactory.filters.NewPool(null, null);
  const event = await elfFactory.queryFilter(filter);
  const elf = Elf__factory.connect(event[0].args?.pool, signer);

  return {
    signer,
    elfFactory,
    usdc,
    yusdc,
    yusdcAsset,
    yusdcAssetVault,
    elf,
    elfStub,
    tranche,
    yc,
  };
}
