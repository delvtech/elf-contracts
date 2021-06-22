import { ethers } from "hardhat";
import { BigNumber } from "ethers";

export const bnFloatMultiplier = (number: BigNumber, multiplier: number) => {
  return number.mul(Math.round(1e10 * multiplier)).div(1e10);
};

export const subError = (amount: BigNumber) => {
  // 1 tenth of a bp of error subbed
  return amount.sub(bnFloatMultiplier(amount, 0.00001));
};
