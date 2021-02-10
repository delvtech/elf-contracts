import {
  createFixtureLoader,
  deployContract,
  MockProvider,
} from "ethereum-waffle";
import {waffle} from "hardhat";
import {Provider} from "@ethersproject/providers";
import {ethers} from "ethers";

import ElfFactoryArtifact from "../../artifacts/contracts/ElfFactory.sol/ElfFactory.json";
import {ElfFactory} from "../../typechain/ElfFactory";

import ElfArtifact from "../../artifacts/contracts/Elf.sol/Elf.json";
import {Elf} from "../../typechain/Elf";

import ATokenArtifact from "../../artifacts/contracts/test/AToken.sol/AToken.json";
import {AToken} from "../../typechain/AToken";

import AYVaultArtifact from "../../artifacts/contracts/test/AYVault.sol/AYVault.json";
import {AYVault} from "../../typechain/AYVault";

import YVaultAssetProxyArtifact from "../../artifacts/contracts/assets/YVaultAssetProxy.sol/YVaultAssetProxy.json";
import {YVaultAssetProxy} from "../../typechain/YVaultAssetProxy";

export const loadFixture = createFixtureLoader();
export interface fixtureInterface {
  owner: ethers.Wallet;
  usdc: AToken;
  yusdc: AYVault;
  yusdcAsset: YVaultAssetProxy;
  elf: Elf;
  elffactory: ElfFactory;
}
export async function basicElfFixture(
  [owner]: ethers.Wallet[],
  provider: Provider
) {
  let elffactory = (await deployContract(
    owner,
    ElfFactoryArtifact,
    []
  )) as ElfFactory;

  let usdc = (await deployContract(owner, ATokenArtifact, [
    owner.address,
  ])) as AToken;

  let yusdc = (await deployContract(owner, AYVaultArtifact, [
    usdc.address,
  ])) as AYVault;

  let yusdcAsset = (await deployContract(owner, YVaultAssetProxyArtifact, [
    yusdc.address,
    usdc.address,
  ])) as YVaultAssetProxy;

  await elffactory.newPool(usdc.address, yusdcAsset.address);

  const filter = await elffactory.filters.NewPool(null, null);
  const event = await elffactory.queryFilter(filter);
  const elf = new ethers.Contract(
    event[0].args?.pool,
    ElfArtifact.abi,
    provider
  ) as Elf;

  return {owner, usdc, yusdc, yusdcAsset, elf, elffactory};
}
