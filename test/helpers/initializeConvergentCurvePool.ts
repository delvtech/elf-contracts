import { BigNumber, ethers, Signer } from "ethers";
import { BytesLike, parseEther } from "ethers/lib/utils";
import { TestERC20 } from "typechain";
import { Tranche } from "typechain/Tranche";
import { JoinPoolRequestStruct, Vault } from "typechain/Vault";

/**
 * the erc20 allowance() method takes a unit256, therefore the max you can approve is 2^256 - 1
 */
const MAX_ALLOWANCE = BigNumber.from(
  "115792089237316195423570985008687907853269984665640564039457584007913129639935"
);
/**
 * Stakes an initial amount of base asset into the YieldPool
 *
 * @param poolId
 * @param elementSigner
 * @param vaultContract
 * @param baseAssetContract
 * @param trancheContract
 * @param amountIn
 */
export async function initializeConvergentCurvePool(
  poolId: string,
  elementSigner: Signer,
  vaultContract: Vault,
  baseAssetContract: TestERC20,
  trancheContract: Tranche,
  amountIn: string
) {
  const elementAddress = await elementSigner.getAddress();
  const { tokens } = await vaultContract.getPoolTokens(poolId);

  // const parseToken = (value: string) => parseUnits(value, baseAssetDecimals);
  // TODO: double check if these should be normalized to Ether or not.  I think balancer wants
  // everything in 18 decimal format so leaving this as parseEther.  If not, then we'll have to use parseToken
  // we can only initialize the pool with base asset, the yield asset is ignored.
  const maxAmountsIn = [parseEther(amountIn), parseEther(amountIn)];
  const amounts = maxAmountsIn.map((amt) => amt.toHexString());

  // Whether or not to use balances held in balancer.  Since The Vault has nothing, set this to false.
  const fromInternalBalance = false;

  // Allow balancer pool to take user's fyt and base tokens
  await baseAssetContract.approve(vaultContract.address, MAX_ALLOWANCE);
  await trancheContract.approve(vaultContract.address, MAX_ALLOWANCE);

  // Balancer V2 vault allows userData as a way to pass props through to pool contracts.  In our
  // case we need to pass the maxAmountsIn.

  const userData: BytesLike = ethers.utils.defaultAbiCoder.encode(
    ["uint256[]"],
    amounts
  );

  const joinPoolRequest: JoinPoolRequestStruct = {
    assets: tokens,
    maxAmountsIn,
    userData,
    fromInternalBalance,
  };

  const joinReceipt = await vaultContract.joinPool(
    poolId,
    elementAddress,
    elementAddress,
    joinPoolRequest
  );

  await joinReceipt.wait(1);
  return joinReceipt;
}
