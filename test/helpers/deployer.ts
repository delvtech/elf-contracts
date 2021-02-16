import {Elf} from "../../typechain/Elf";
import {ElfFactory} from "../../typechain/ElfFactory";
import {AToken} from "../../typechain/AToken";
import {AYVault} from "../../typechain/AYVault";
import {YVaultAssetProxy} from "../../typechain/YVaultAssetProxy";
import ElfArtifact from "../../artifacts/contracts/Elf.sol/Elf.json";

import {Signer} from "ethers";
import {ethers} from "hardhat";

export interface fixtureInterface {
  signer: Signer;
  elfFactory: ElfFactory;
  usdc: AToken;
  yusdc: AYVault;
  yusdcAsset: YVaultAssetProxy;
  elf: Elf;
}

const deployElfFactory = async (signer: Signer) => {
  const deployer = await ethers.getContractFactory("ElfFactory", signer);
  return (await deployer.deploy()) as ElfFactory;
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
  const elfFactory = (await deployElfFactory(signer)) as ElfFactory;
  const usdc = (await deployUsdc(signer, signerAddress)) as AToken;
  const yusdc = (await deployYusdc(signer, usdc.address)) as AYVault;
  const yusdcAsset = (await deployYusdcAsset(
    signer,
    yusdc.address,
    usdc.address
  )) as YVaultAssetProxy;

  await elfFactory.newPool(
    usdc.address,
    yusdcAsset.address,
    "Element yUSDC",
    "eyUSDC"
  );

  const filter = await elfFactory.filters.NewPool(null, null);
  const event = await elfFactory.queryFilter(filter);
  const elf = new ethers.Contract(
    event[0].args?.pool,
    ElfArtifact.abi,
    ethers.provider
  ) as Elf;

  return {signer, elfFactory, usdc, yusdc, yusdcAsset, elf};
}
