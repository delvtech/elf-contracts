import hre from "hardhat";

import {Elf} from "../../typechain/Elf";
import {ElfFactory} from "../../typechain/ElfFactory";
import {AToken} from "../../typechain/AToken";
import {AYVault} from "../../typechain/AYVault";
import {YVaultAssetProxy} from "../../typechain/YVaultAssetProxy";
import ElfArtifact from "../../artifacts/contracts/Elf.sol/Elf.json";

import {Signer} from "ethers";

export interface fixtureInterface {
  signer: Signer;
  elfFactory: ElfFactory;
  usdc: AToken;
  yusdc: AYVault;
  yusdcAsset: YVaultAssetProxy;
  elf: Elf;
}

const deployElfFactory = async (signer: Signer) => {
  const deployer = await hre.ethers.getContractFactory("ElfFactory", signer);
  return (await deployer.deploy()) as ElfFactory;
};

const deployUsdc = async (signer: Signer, owner: string) => {
  const deployer = await hre.ethers.getContractFactory("AToken", signer);
  return (await deployer.deploy(owner)) as AToken;
};

const deployYusdc = async (signer: Signer, usdcAddress: string) => {
  const deployer = await hre.ethers.getContractFactory("AYVault", signer);
  return (await deployer.deploy(usdcAddress)) as AYVault;
};

const deployYusdcAsset = async (
  signer: Signer,
  yusdcAddress: string,
  usdcAddress: string
) => {
  const deployer = await hre.ethers.getContractFactory(
    "YVaultAssetProxy",
    signer
  );
  return (await deployer.deploy(yusdcAddress, usdcAddress)) as YVaultAssetProxy;
};

export async function loadFixture() {
  const [signer] = await hre.ethers.getSigners();
  const signerAddress = (await signer.getAddress()) as string;
  const elfFactory = (await deployElfFactory(signer)) as ElfFactory;
  const usdc = (await deployUsdc(signer, signerAddress)) as AToken;
  const yusdc = (await deployYusdc(signer, usdc.address)) as AYVault;
  const yusdcAsset = (await deployYusdcAsset(
    signer,
    yusdc.address,
    usdc.address
  )) as YVaultAssetProxy;

  await elfFactory.newPool(usdc.address, yusdcAsset.address);

  const filter = await elfFactory.filters.NewPool(null, null);
  const event = await elfFactory.queryFilter(filter);
  const elf = new hre.ethers.Contract(
    event[0].args?.pool,
    ElfArtifact.abi,
    hre.ethers.provider
  ) as Elf;

  return {signer, elfFactory, usdc, yusdc, yusdcAsset, elf};
}
