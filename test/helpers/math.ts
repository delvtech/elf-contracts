import { BigNumber } from "ethers";

export const bnFloatMultiplier = (number: BigNumber, multiplier: number) => {
  return number.mul(Math.round(1e10 * multiplier)).div(1e10);
};

export const subError = (amount: BigNumber) => {
  // 1 tenth of a bp of error subbed
  return amount.sub(bnFloatMultiplier(amount, 0.00001));
};

export function calcBigNumberPercentage(
  amount: BigNumber,
  percentage: number
): BigNumber {
  if (isNaN(percentage) || percentage < 0) {
    throw new Error("not a valid percentage");
  }

  const percentageStr = percentage.toString();
  const denomString = "100";
  let scaleAmount = 0;

  const dotPosition = percentageStr.indexOf(".");
  if (dotPosition !== -1) {
    scaleAmount = +(percentageStr.length - 1);
  }
  const multiplier = scaleAmount > 0 ? 10 ** scaleAmount : 1;
  const numerator = percentage * multiplier;
  const denominator = +denomString * multiplier;

  return amount.mul(BigNumber.from(numerator)).div(denominator);
}
