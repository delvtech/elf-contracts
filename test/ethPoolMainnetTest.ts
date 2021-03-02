import {ethers} from "hardhat";

import {
  loadEthPoolMainnetFixture,
  ethPoolMainnetInterface,
} from "./helpers/deployer";
import {createSnapshot, restoreSnapshot} from "./helpers/snapshots";
import {impersonate} from "./helpers/impersonate";

import {expect} from "chai";
import {Signer} from "ethers";

const {waffle} = require("hardhat");
const provider = waffle.provider;

describe("ETHPool-Mainnet", () => {
  let users: {user: Signer; address: string}[];
  let fixture: ethPoolMainnetInterface;
  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts
    fixture = await loadEthPoolMainnetFixture();

    // begin to populate the user array by assigning each index a signer
    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return {user, address: ""};
    });

    // We load and impersonate the governance of the yweth contract
    const yearnGovAddress = await fixture.yweth.governance();
    impersonate(yearnGovAddress);
    const yearnGov = ethers.provider.getSigner(yearnGovAddress);
    // We set the deposit limit to very high
    fixture.yweth
      .connect(yearnGov)
      .setDepositLimit(ethers.utils.parseEther("100000000000"));

    // finish populating the user array by assigning each index a signer address
    await Promise.all(
      users.map(async (userInfo) => {
        let user = userInfo.user;
        userInfo.address = await user.getAddress();
      })
    );
    await fixture.weth
      .connect(users[1].user)
      .deposit({value: ethers.utils.parseEther("20000")});
    await fixture.weth
      .connect(users[1].user)
      .approve(fixture.elf.address, ethers.utils.parseEther("20000"));
    await fixture.weth
      .connect(users[2].user)
      .deposit({value: ethers.utils.parseEther("20000")});
    await fixture.weth
      .connect(users[2].user)
      .approve(fixture.elf.address, ethers.utils.parseEther("20000"));
    await fixture.weth
      .connect(users[3].user)
      .deposit({value: ethers.utils.parseEther("60000")});
    await fixture.weth
      .connect(users[3].user)
      .approve(fixture.elf.address, ethers.utils.parseEther("60000"));
  });
  after(async () => {
    // revert back to initial state after all tests pass
    await restoreSnapshot(provider);
  });
  beforeEach(async () => {
    await createSnapshot(provider);
  });
  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("deposit + withdraw", () => {
    it("should correctly handle deposits and withdrawals", async () => {
      await fixture.elf
        .connect(users[1].user)
        .deposit(users[1].address, ethers.utils.parseEther("10000"));
      await fixture.elf
        .connect(users[2].user)
        .deposit(users[2].address, ethers.utils.parseEther("20000"));
      await fixture.elf
        .connect(users[1].user)
        .deposit(users[1].address, ethers.utils.parseEther("10000"));
      await fixture.elf
        .connect(users[3].user)
        .deposit(users[3].address, ethers.utils.parseEther("60000"));

      let pricePerFullShare = await fixture.yweth.pricePerShare();
      const balance = (
        await (await fixture.yweth.balanceOf(fixture.elf.address)).mul(
          pricePerFullShare
        )
      ).div(ethers.utils.parseEther("1"));
      expect(balance.add(ethers.BigNumber.from("5"))).to.be.at.least(
        ethers.BigNumber.from("1000000000000")
      );

      /* At this point:
       *         deposited     held
       * User 1: 20,000 weth | 0 weth
       * user 2: 20,000 weth | 0 weth
       * User 3: 60,000 weth | 0 weth
       */

      // Test a transfer
      let user1Balance = await fixture.elf.balanceOf(users[1].address);
      let user3Balance = await fixture.elf.balanceOf(users[3].address);
      await fixture.elf
        .connect(users[3].user)
        .transfer(users[1].address, user3Balance.div(ethers.BigNumber.from(2)));
      expect(
        (await fixture.elf.balanceOf(users[1].address)).add(
          await fixture.elf.balanceOf(users[3].address)
        )
      ).to.equal(user1Balance.add(user3Balance));

      /* At this point:
       *         deposited     held
       * User 1: 50,000 weth | 0 weth
       * user 2: 20,000 weth | 0 weth
       * User 3: 30,000 weth | 0 weth
       */

      // Test withdraws

      const toWithdraw = ethers.utils.parseEther("1");
      user1Balance = await fixture.elf.balanceOf(users[1].address);
      pricePerFullShare = await fixture.yweth.pricePerShare();
      const withdrawWeth = toWithdraw
        .mul(pricePerFullShare)
        .div(ethers.utils.parseEther("1"));

      await fixture.elf
        .connect(users[1].user)
        .withdraw(users[1].address, toWithdraw, 0);
      expect(await fixture.elf.balanceOf(users[1].address)).to.equal(
        user1Balance.sub(toWithdraw)
      );
      expect(await fixture.weth.balanceOf(users[1].address)).to.equal(
        withdrawWeth
      );

      /* At this point:
       *         deposited     held
       * User 1: 49,999 weth | 1 weth
       * user 2: 20,000 weth | 0 weth
       * User 3: 30,000 weth | 0 weth
       */

      const elfBalanceU1 = await fixture.elf.balanceOf(users[1].address);
      await fixture.elf
        .connect(users[1].user)
        .withdraw(users[1].address, elfBalanceU1, 0);
      expect(await fixture.elf.balanceOf(users[1].address)).to.equal(0);

      const elfBalanceU2 = await fixture.elf.balanceOf(users[2].address);
      await fixture.elf
        .connect(users[2].user)
        .withdraw(users[2].address, elfBalanceU2, 0);
      expect(await fixture.elf.balanceOf(users[2].address)).to.equal(0);

      const elfBalanceU3 = await fixture.elf.balanceOf(users[3].address);
      await fixture.elf
        .connect(users[3].user)
        .withdraw(users[3].address, elfBalanceU3, 0);
      expect(await fixture.elf.balanceOf(users[3].address)).to.equal(0);

      /* At this point:
       *         deposited     held
       * User 1: 0 weth      | 50,000 weth
       * user 2: 0 weth      | 20,000 weth
       * User 3: 0 weth      | 30,000 weth
       */

      const finalWethBalanceU1 = await fixture.weth.balanceOf(users[1].address);
      const finalWethBalanceU2 = await fixture.weth.balanceOf(users[2].address);
      const finalWethBalanceU3 = await fixture.weth.balanceOf(users[3].address);
      expect(
        finalWethBalanceU1
          .add(finalWethBalanceU2)
          .add(finalWethBalanceU3)
          .add(ethers.BigNumber.from("5"))
      ).to.be.at.least(ethers.utils.parseEther("100000"));
    });
  });

  describe("balance", () => {
    it("should return the correct balance", async () => {
      await fixture.elf
        .connect(users[1].user)
        .deposit(users[1].address, ethers.utils.parseEther("10000"));

      const pricePerFullShare = await fixture.yweth.pricePerShare();
      const balance = (await fixture.yweth.balanceOf(fixture.elf.address))
        .mul(pricePerFullShare)
        .div(ethers.utils.parseEther("1"));

      // Sub 1 ETH for 0.01% loss due to high volume deposit
      expect(balance).to.be.at.least(ethers.utils.parseEther("9999"));
    });
  });
});
