import "module-alias/register";

import { Signer } from "ethers";

import { Vault__factory } from "typechain/factories/Vault__factory";

export async function deployBalancerVault(signer: Signer, wethAddress: string) {
  const signerAddress = await signer.getAddress();
  const vaultDeployer = new Vault__factory(signer);
  const vaultContract = await vaultDeployer.deploy(
    signerAddress,
    wethAddress,
    0,
    0
  );

  await vaultContract.deployed();

  return vaultContract;
}
