import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { Contract } from "ethers";
import { ethers } from "hardhat";

import { loadFixture } from "./helpers/deployer";

describe("UserProxyTests", function () {
  let fixture: fixtureInterface;
  let tranche: Contract;
  let proxy: Contract;
  let underlying: Contract;
  let signers: SignerWithAddress[];
  const fakeAddress = "0x7109709ECfa91a80626fF3989D68f67F5b1DD12D";
  const lots = ethers.utils.parseEther("1000000000000");

  before(async function () {
    // Get the setup contracts
    fixture = await loadFixture();
    tranche = fixture.tranche;
    proxy = fixture.proxy;

    underlying = await ethers.getContractAt(
      "AToken",
      await fixture.elf.token()
    );
    // Get the signers
    signers = await ethers.getSigners();
    // mint to the user 0
    await underlying.mint(signers[0].address, lots);
    // mint to the user 1
    await underlying.mint(signers[1].address, lots);
  });

  it("Successfully mints", async function () {
    // To avoid messing with permit we use the allowance method
    await underlying.approve(proxy.address, lots);
    let receipt = await proxy.mint(
      ethers.utils.parseEther("1"),
      underlying.address,
      5000,
      fixture.elf.address
    );
    // Mint for the first time
    receipt = await receipt.wait();
    console.log("First Mint", receipt.gasUsed.toNumber());
    receipt = await proxy.mint(
      ethers.utils.parseEther("1"),
      underlying.address,
      5000,
      fixture.elf.address
    );
    receipt = await receipt.wait();
    console.log("Repeat Mint", receipt.gasUsed.toNumber());
    // Set an approval for the new user
    await underlying.connect(signers[1]).approve(proxy.address, lots);
    receipt = await proxy
      .connect(signers[1])
      .mint(
        ethers.utils.parseEther("1"),
        underlying.address,
        5000,
        fixture.elf.address
      );
    receipt = await receipt.wait();
    console.log("New User First mint", receipt.gasUsed.toNumber());
  });
});
