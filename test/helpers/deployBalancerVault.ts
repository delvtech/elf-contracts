import { Signer } from "ethers";

import { Vault__factory } from "../../typechain/factories/Vault__factory";

export async function deployBalancerVault(signer: Signer) {
  const signerAddress = await signer.getAddress();
  const vaultDeployer = new Vault__factory(signer);
  const vaultContract = await vaultDeployer.deploy(signerAddress);

  await vaultContract.deployed();

  return vaultContract;
}
