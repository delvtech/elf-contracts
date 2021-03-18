import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { TestERC20 } from "typechain/TestERC20";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { PERMIT_TYPEHASH } from "./helpers/signatures";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

describe("erc20", function () {
  let token: TestERC20;
  before(async function () {
    await createSnapshot(provider);
    const [signer] = await ethers.getSigners();
    const deployer = new TestERC20__factory(signer);
    token = await deployer.deploy("token", "TKN", 18);
  });
  after(async () => {
    await restoreSnapshot(provider);
  });
  beforeEach(async () => {
    await createSnapshot(provider);
  });
  afterEach(async () => {
    await restoreSnapshot(provider);
  });
  it("has a correctly precomputed typehash", async function () {
    expect(await token.PERMIT_TYPEHASH()).to.equal(PERMIT_TYPEHASH);
  });
});
