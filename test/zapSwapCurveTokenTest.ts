import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { setBlock } from "./helpers/forking";
import { createSnapshot } from "./helpers/snapshots";
import { UserProxy__factory } from "typechain/factories/UserProxy__factory";
import { Vault__factory } from "typechain/factories/Vault__factory";
import { ZapSwapCurveToken__factory } from "typechain/factories/ZapSwapCurveToken.sol";

const { provider } = waffle;

const ZAP_BLOCK = 13583600;

export async function deploy(user: { user: Signer; address: string }) {
  const [authSigner] = await ethers.getSigners();
  const balancerVault = Vault__factory.connect(
    "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    user.user
  );

  const proxy = UserProxy__factory.connect(
    "0xEe4e158c03A10CBc8242350d74510779A364581C",
    user.user
  );
}

describe("ZapCurveTokenToPrincipalToken", () => {
  let users: { user: Signer; address: string }[];

  let initBlock: number;

  before(async () => {
    initBlock = await provider.getBlockNumber();
    await createSnapshot(provider);
    // Do not change block as dependencies might change
    await setBlock(ZAP_BLOCK);

    users = ((await ethers.getSigners()) as Signer[]).map((user) => ({
      user,
      address: "",
    }));

    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    // ({
    //   zapCurveTokenToPrincipalToken,
    //   constructZapInArgs,
    //   constructZapOutArgs,
    // } = await deploy(users[1]));
  });
});
