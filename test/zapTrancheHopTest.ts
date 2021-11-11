import { expect } from "chai";
import { Signer, BigNumberish } from "ethers";
import { ethers, waffle } from "hardhat";
import { loadTrancheHopFixture, TrancheHopInterface } from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime } from "./helpers/time";
import { impersonate, stopImpersonating } from "./helpers/impersonate";

const { provider } = waffle;

describe("zapTrancheHop", () => {
  let users: { user: Signer; address: string }[];
  let fixture: TrancheHopInterface;

  // send `amount` of shares directly to the yearn vault simulating interest.
  async function yearnInterestSim(amount: BigNumberish) {
    const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";
    impersonate(usdcWhaleAddress);
    const lpSigner = ethers.provider.getSigner(usdcWhaleAddress);
    await fixture.usdc
      .connect(lpSigner)
      .transfer(fixture.yusdc.address, amount);
  }

  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // begin to populate the user array by assigning each index a signer
    users = ((await ethers.getSigners()) as Signer[]).map(function (user) {
      return { user, address: "" };
    });

    // finish populating the user array by assigning each index a signer address
    await Promise.all(
      users.map(async (userInfo) => {
        const { user } = userInfo;
        userInfo.address = await user.getAddress();
      })
    );

    fixture = await loadTrancheHopFixture(users[1].address);
    // get USDC
    const usdcWhaleAddress = "0xAe2D4617c862309A3d75A0fFB358c7a5009c673F";
    impersonate(usdcWhaleAddress);
    const usdcWhale = ethers.provider.getSigner(usdcWhaleAddress);
    await fixture.usdc.connect(usdcWhale).transfer(users[1].address, 2e11); // 200k usdc
    stopImpersonating(usdcWhaleAddress);
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
  describe("rescueTokens", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should correctly rescue ERC20", async () => {
      const inputValue = 100000000;
      await fixture.usdc
        .connect(users[1].user)
        .transfer(fixture.trancheHop.address, inputValue);
      const initialBalance = await fixture.usdc.balanceOf(users[1].address);
      // send 100 USDC to the zapper and attempt to rescue it
      await fixture.trancheHop
        .connect(users[1].user)
        .rescueTokens(fixture.usdc.address, inputValue);
      const finalBalance = await fixture.usdc.balanceOf(users[1].address);
      expect(finalBalance).to.be.at.least(initialBalance.add(inputValue));
    });
  });
  describe("hopToTranche", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
      await fixture.usdc
        .connect(users[1].user)
        .approve(fixture.tranche1.address, 1e11);
      await fixture.tranche1
        .connect(users[1].user)
        .deposit(1e11, users[1].address);
      // add some interest so YTs are redeemable
      yearnInterestSim(1000000000000);
      // move first tranche to expiration
      advanceTime(provider, 1e10);
    });

    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should revert if the contract is frozen", async () => {
      await fixture.trancheHop.connect(users[1].user).setIsFrozen(true);
      const tx = fixture.trancheHop
        .connect(users[1].user)
        .hopToTranche(
          fixture.usdc.address,
          fixture.position.address,
          0,
          fixture.position.address,
          0,
          0,
          0,
          0,
          0
        );

      await expect(tx).to.be.revertedWith("Contract frozen");
    });
    it("should fail to hop with insufficient PT minted", async () => {
      const ptBalanceT1 = await fixture.tranche1.balanceOf(users[1].address);
      const ytBalanceT1 = await fixture.interestToken1.balanceOf(
        users[1].address
      );

      await fixture.tranche1
        .connect(users[1].user)
        .approve(fixture.trancheHop.address, ptBalanceT1);
      await fixture.interestToken1
        .connect(users[1].user)
        .approve(fixture.trancheHop.address, ytBalanceT1);

      const tx = fixture.trancheHop
        .connect(users[1].user)
        .hopToTranche(
          fixture.usdc.address,
          fixture.position.address,
          1e10,
          fixture.position.address,
          2e10,
          ptBalanceT1,
          ytBalanceT1,
          1e12,
          1
        );
      await expect(tx).to.be.revertedWith("Not enough PT minted");
    });
    it("should fail to hop with insufficient YT minted", async () => {
      const ptBalanceT1 = await fixture.tranche1.balanceOf(users[1].address);
      const ytBalanceT1 = await fixture.interestToken1.balanceOf(
        users[1].address
      );

      await fixture.tranche1
        .connect(users[1].user)
        .approve(fixture.trancheHop.address, ptBalanceT1);
      await fixture.interestToken1
        .connect(users[1].user)
        .approve(fixture.trancheHop.address, ytBalanceT1);

      const tx = fixture.trancheHop
        .connect(users[1].user)
        .hopToTranche(
          fixture.usdc.address,
          fixture.position.address,
          1e10,
          fixture.position.address,
          2e10,
          ptBalanceT1,
          ytBalanceT1,
          1,
          1e12
        );
      await expect(tx).to.be.revertedWith("Not enough YT minted");
    });
    it("should correctly hop tranches", async () => {
      const ptBalanceT1 = await fixture.tranche1.balanceOf(users[1].address);
      const ytBalanceT1 = await fixture.interestToken1.balanceOf(
        users[1].address
      );

      await fixture.tranche1
        .connect(users[1].user)
        .approve(fixture.trancheHop.address, ptBalanceT1);
      await fixture.interestToken1
        .connect(users[1].user)
        .approve(fixture.trancheHop.address, ytBalanceT1);

      await fixture.trancheHop
        .connect(users[1].user)
        .hopToTranche(
          fixture.usdc.address,
          fixture.position.address,
          1e10,
          fixture.position.address,
          2e10,
          ptBalanceT1,
          ytBalanceT1,
          1,
          1
        );

      const ptBalanceT2 = await fixture.tranche2.balanceOf(users[1].address);
      const ytBalanceT2 = await fixture.interestToken2.balanceOf(
        users[1].address
      );

      // no interest accumulated in new tranche so no PT discounting
      expect(ptBalanceT2).to.equal(ytBalanceT2);
      expect(ptBalanceT2).to.be.at.least(1);
    });
  });
});
