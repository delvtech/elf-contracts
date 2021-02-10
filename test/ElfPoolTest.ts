import {ethers, waffle} from "hardhat";
import {BigNumber, Signer} from "ethers";

import chai from "chai";
import {solidity} from "ethereum-waffle";
import {createSnapshot, restoreSnapshot} from "./helpers/snapshots";
import {AddressZero} from "@ethersproject/constants";
import {
  basicElfFixture,
  loadFixture,
  fixtureInterface,
} from "./fixtures/fixtures";

chai.use(solidity);
const {expect} = chai;
const {provider} = waffle;

describe("ElfPoolTest", () => {
  let users: {user: Signer; address: string}[];
  let fixture: fixtureInterface;
  before(async () => {
    // get an array of users
    //users = await ethers.getSigners()
    fixture = await loadFixture(basicElfFixture);

    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return {user, address: ""};
    });

    await Promise.all(
      users.map(async (userInfo) => {
        let user = userInfo.user;
        userInfo.address = await user.getAddress();
        console.log(userInfo.address);
        await fixture.usdc.connect(user).mint(userInfo.address, 6e6);
        await fixture.usdc.connect(user).approve(fixture.elf.address, 6e6);
        let balUsdc = await fixture.usdc.balanceOf(userInfo.address);
        console.log(balUsdc);
      })
    );
  });

  describe("setGovernance", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should only be callable by governance contract", async () => {
      // await expect(fixture.elf.connect(users[0].user).setGovernance(AddressZero)).to.be.revertedWith("!governance")
      await fixture.elf.connect(fixture.owner).setGovernance(AddressZero);
      expect(await fixture.elf.governance()).to.equal(AddressZero);
    });
  });

  describe("deposit", () => {
    before(async () => {
      await fixture.yusdcAsset
        .connect(fixture.owner)
        .setPool(fixture.elf.address);
    });
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("correctly tracks deposited value", async () => {
      //await fixture.elf.connect(users[0].user).deposit(users[0].address, 1e6)
      let tx = await (
        await fixture.usdc.connect(users[0].user).mint(users[0].address, 6e6)
      ).wait();
      console.log(tx);
      let balUsdc = await fixture.usdc.balanceOf(users[0].address);
      console.log(balUsdc);
      //expect().to.equal(1e6)

      // await fixture.elf.connect(users[1].user).deposit(users[1].address, 1e6)
      // expect(await fixture.elf.balanceOf(users[1].address)).to.equal(1e6)
    });
  });
});
