import {ethers} from "hardhat";
import {BigNumber} from "ethers";

export const bnFloatMultiplier = (number: BigNumber, mulpiplier: number) => {
  return ethers.BigNumber.from(
    Math.round(number.toNumber() * mulpiplier).toString()
  );
};
