import { BigNumber } from "ethers";
import { ethers, waffle } from "hardhat";
import { ERC20__factory } from "typechain/factories/ERC20__factory";

const { provider } = waffle;

export enum ContractLanguage {
  Solidity,
  Vyper,
}

// findBalancesSlot works by iterating across the first 100 slots for a given
// contract address. Notwithstanding a minute difference in mapping
// construction in solidity versus vyper contract, it works in each case by
// updating a potential balance slot, checking the balance for the test address
// (the zero address), and then seeing if matches. After each check, the slot is
// reset to its original value
async function findBalancesSlot(
  address: string,
  lang: ContractLanguage
): Promise<number> {
  const account = ethers.constants.AddressZero;
  const probeA = ethers.utils.defaultAbiCoder.encode(["uint"], [1]);
  const probeB = ethers.utils.defaultAbiCoder.encode(["uint"], [2]);

  const token = ERC20__factory.connect(address, provider);

  for (let i = 0; i < 100; i++) {
    let probedSlot = ethers.utils.keccak256(
      lang === ContractLanguage.Solidity
        ? ethers.utils.defaultAbiCoder.encode(["address", "uint"], [account, i])
        : ethers.utils.defaultAbiCoder.encode(["uint", "address"], [i, account])
    );

    if (probedSlot.startsWith("0x0")) probedSlot = "0x" + probedSlot.slice(3);

    const prev = await provider.send("eth_getStorageAt", [
      address,
      probedSlot,
      "latest",
    ]);

    const probe = prev === probeA ? probeB : probeA;

    await provider.send("hardhat_setStorageAt", [address, probedSlot, probe]);

    const balance = await token.balanceOf(account);

    await provider.send("hardhat_setStorageAt", [address, probedSlot, prev]);

    if (balance.eq(ethers.BigNumber.from(probe))) return i;
  }
  throw "Balances slot not found!";
}

export default async function manipulateTokenBalance(
  address: string,
  lang: ContractLanguage,
  amount: BigNumber,
  recipient: string
) {
  const slot = await findBalancesSlot(address, lang);

  const index = ethers.utils.solidityKeccak256(
    ["uint256", "uint256"],
    lang === ContractLanguage.Solidity ? [recipient, slot] : [slot, recipient]
  );

  await provider.send("hardhat_setStorageAt", [
    address,
    index,
    ethers.utils.defaultAbiCoder.encode(["uint"], [amount]),
  ]);
}
