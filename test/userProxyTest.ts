import { expect } from "chai";
import { ethers } from "hardhat";
import {
  loadUsdcPoolMainnetFixture,
  UsdcPoolMainnetInterface,
} from "./helpers/deployer";
import { impersonate } from "./helpers/impersonate";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

describe("UserProxyTests", function () {
  let fixture: UsdcPoolMainnetInterface;
  let proxy: Contract;
  let underlying: Contract;
  let signers: SignerWithAddress[];
  const lots = ethers.utils.parseUnits("1000000", 6);
  const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";

  before(async function () {
    // Get the setup contracts
    fixture = await loadUsdcPoolMainnetFixture();
    ({ proxy } = fixture);

    underlying = await ethers.getContractAt(
      "contracts/libraries/ERC20.sol:ERC20",
      await fixture.elf.token()
    );
    impersonate(usdcWhaleAddress);
    const usdcWhale = await ethers.provider.getSigner(usdcWhaleAddress);
    // Get the signers
    signers = await ethers.getSigners();
    // mint to the user 0
    await underlying.connect(usdcWhale).transfer(signers[0].address, lots);
    // mint to the user 1
    await underlying.connect(usdcWhale).transfer(signers[1].address, lots);

    // Make an initial deposit in the aypool contract
    // This prevents a div by zero reversion in several cases
    await fixture.usdc.connect(usdcWhale).transfer(signers[0].address, 100);
    await fixture.usdc.approve(fixture.yusdc.address, 100);
    await fixture.yusdc.deposit(100, signers[0].address);

    // Make a gas reserve deposit to test that logic
    const twohundred = ethers.utils.parseUnits("200", 6);
    await fixture.usdc
      .connect(usdcWhale)
      .approve(fixture.elf.address, twohundred.mul(2));
    await fixture.elf.connect(usdcWhale).reserveDeposit(twohundred);
  });
  it("Successfully derives tranche contract address", async function () {
    const addr = await fixture.proxy.deriveTranche(fixture.elf.address, 1e10);
    expect(addr).to.equal(fixture.tranche.address);
  });
  it("Successfully mints", async function () {
    // To avoid messing with permit we use the allowance method
    await underlying.approve(proxy.address, lots);

    let receipt = await proxy.mint(
      ethers.utils.parseUnits("1", 6),
      underlying.address,
      1e10,
      fixture.elf.address
    );
    // Mint for the first time
    receipt = await receipt.wait();
    console.log("First Mint", receipt.gasUsed.toNumber());
    receipt = await proxy.mint(
      ethers.utils.parseUnits("1", 6),
      underlying.address,
      1e10,
      fixture.elf.address
    );
    receipt = await receipt.wait();
    console.log("Repeat Mint", receipt.gasUsed.toNumber());
    // Set an approval for the new user
    await underlying.connect(signers[1]).approve(proxy.address, lots);
    receipt = await proxy
      .connect(signers[1])
      .mint(
        ethers.utils.parseUnits("1", 6),
        underlying.address,
        1e10,
        fixture.elf.address
      );
    receipt = await receipt.wait();
    console.log("New User First mint", receipt.gasUsed.toNumber());
  });
});
