import hre from "hardhat";
import { ethers } from "hardhat";

export const impersonate = async (address: string) => {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  const signer = ethers.provider.getSigner(address);
  return signer;
};

export const stopImpersonating = async (address: string) => {
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [address],
  });
};
