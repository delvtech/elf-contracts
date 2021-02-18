import {ethers} from "hardhat";
import {loadFixture, fixtureInterface} from "./helpers/deployer";
import {expect} from "chai";
import {Contract} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

describe("UserProxyTests", function () {
  let fixture;
  let tranche: Contract;
  let proxy: Contract;
  let underlying: Contract;
  let signers: SignerWithAddress[];
  const fakeAddress = "0x7109709ECfa91a80626fF3989D68f67F5b1DD12D";
  const lots = ethers.utils.parseEther("1000000000000");

  before(async function () {
    // Get the setup contracts
    fixture = await loadFixture();
    const trancheFactory = await ethers.getContractFactory("Tranche");
    tranche = await trancheFactory.deploy(fixture.elf.address, 500000);
    // Setup the proxy
    const proxyFactory = await ethers.getContractFactory("UserProxyTest");
    // Without a real weth address this can't accept eth deposits
    proxy = await proxyFactory.deploy(
      fakeAddress,
      fixture.elf.address,
      tranche.address
    );
    underlying = await ethers.getContractAt(
      "AToken",
      await fixture.elf.token()
    );
    // Since the internal lookup method are overridden we can provide
    // any data to the first param
    await proxy.allowElf(underlying.address, fakeAddress);
    // Since the internal lookup method are overridden we can provide
    // any data
    await proxy.allowTranche(fakeAddress, 0);
    // Get the signers
    signers = await ethers.getSigners();
    // mint to the user 0
    await underlying.mint(signers[0].address, lots);
    // mint to the user 1
    await underlying.mint(signers[1].address, lots);
    // Set the pool to actually be the ELF
    await fixture.yusdcAsset.setPool(fixture.elf.address);
  });

  it("Successfully mints", async function () {
    // To avoid messing with permit we use the allowance method
    await underlying.approve(proxy.address, lots);
    let receipt = await proxy.mint(
      ethers.utils.parseEther("1"),
      underlying.address,
      5000,
      fakeAddress
    );
    // Mint for the first time
    receipt = await receipt.wait();
    console.log("First Mint", receipt.gasUsed.toNumber());
    receipt = await proxy.mint(
      ethers.utils.parseEther("1"),
      underlying.address,
      5000,
      fakeAddress
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
        fakeAddress
      );
    receipt = await receipt.wait();
    console.log("New User First mint", receipt.gasUsed.toNumber());
  });
});
