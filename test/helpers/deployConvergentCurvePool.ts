import { Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { THIRTY_DAYS_IN_SECONDS } from "test/helpers/time";
import { ERC20 } from "typechain/ERC20";
import { ConvergentCurvePool__factory } from "typechain/factories/ConvergentCurvePool__factory";
import { Vault } from "typechain/Vault";

const defaultOptions = {
  swapFee: ".003",
  durationInSeconds: THIRTY_DAYS_IN_SECONDS,
};

export async function deployConvergentCurvePool(
  signer: Signer,
  vaultContract: Vault,
  baseAssetContract: ERC20,
  yieldAssetContract: ERC20,
  options?: {
    swapFee: string;
    durationInSeconds: number;
  }
) {
  const { swapFee, durationInSeconds } = { ...defaultOptions, ...options };
  const elementAddress = await signer.getAddress();
  const baseAssetSymbol = await baseAssetContract.symbol();
  const curcePoolDeployer = new ConvergentCurvePool__factory(signer);

  const dateInMilliseconds = Date.now();
  const dateInSeconds = dateInMilliseconds / 1000;
  const expiration = Math.round(dateInSeconds + durationInSeconds);

  const poolContract = await curcePoolDeployer.deploy(
    baseAssetContract.address,
    yieldAssetContract.address,
    expiration,
    durationInSeconds,
    vaultContract.address,
    parseEther(swapFee),
    elementAddress,
    `Element ${baseAssetSymbol} - fy${baseAssetSymbol}`,
    `${baseAssetSymbol}-fy${baseAssetSymbol}`
  );

  // grab last poolId from last event
  const newPools = vaultContract.filters.PoolCreated(null);
  const results = await vaultContract.queryFilter(newPools);
  const poolIds: string[] = results.map((result) => result.args?.poolId);
  const poolId = poolIds[poolIds.length - 1];

  return { poolId, poolContract };
}
