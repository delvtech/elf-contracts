import { ethers } from "hardhat";
import { BigNumber } from "ethers";

export const bnFloatMultiplier = (number: BigNumber, mulpiplier: number) => {
  return ethers.BigNumber.from(
    Math.round(number.toNumber() * mulpiplier).toString()
  );
};

export const subError = (amount: BigNumber) => {
  // 1 tenth of a bp of error subbed
  return amount.sub(bnFloatMultiplier(amount, 0.00001));
};
