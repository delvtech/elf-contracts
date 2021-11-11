import { Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { THIRTY_DAYS_IN_SECONDS } from "test/helpers/time";
import { TestConvergentCurvePool__factory } from "typechain/factories/TestConvergentCurvePool__factory";
import { TestERC20 } from "typechain/TestERC20";
import { Vault } from "typechain/Vault";

const defaultOptions = {
  swapFee: ".003",
  durationInSeconds: THIRTY_DAYS_IN_SECONDS,
};

export async function deployConvergentCurvePool(
  signer: Signer,
  vaultContract: Vault,
  baseAssetContract: TestERC20,
  yieldAssetContract: TestERC20,
  options?: {
    swapFee: string;
    expiration: number;
    durationInSeconds: number;
  }
) {
  const {
    expiration: providedExpiration,
    swapFee,
    durationInSeconds,
  } = {
    ...defaultOptions,
    ...options,
  };
  const elementAddress = await signer.getAddress();
  const baseAssetSymbol = await baseAssetContract.symbol();
  const curvePoolDeployer = new TestConvergentCurvePool__factory(signer);

  const dateInMilliseconds = Date.now();
  const dateInSeconds = dateInMilliseconds / 1000;
  const defaultExpiration = Math.round(dateInSeconds + durationInSeconds);
  const expiration = providedExpiration ?? defaultExpiration;

  const poolContract = await curvePoolDeployer.deploy(
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
  const newPools = vaultContract.filters.PoolRegistered(null, null, null);
  const results = await vaultContract.queryFilter(newPools);
  const poolIds: string[] = results.map((result) => result.args?.poolId);
  const poolId = poolIds[poolIds.length - 1];

  return { poolId, poolContract };
}
