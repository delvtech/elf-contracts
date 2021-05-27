import { expect } from "chai";
import { Signer, BigNumber, BigNumberish } from "ethers";
import { ethers, waffle } from "hardhat";

import {
  loadStethPoolMainnetFixture,
  StethPoolMainnetInterface,
} from "./helpers/deployer";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { advanceTime, getCurrentTimestamp } from "./helpers/time";
import { impersonate, stopImpersonating } from "./helpers/impersonate";
import { subError, bnFloatMultiplier } from "./helpers/math";

const { provider } = waffle;

describe("zap-stethCRV-Mainnet", () => {
  let users: { user: Signer; address: string }[];
  let fixture: StethPoolMainnetInterface;
  let stethSigner: Signer;

  async function yearnInterestSim(amount: BigNumberish) {
    const lpWhale = "0xa2fa3589df392e3a15e1e801f62dafcb3aa0dc0a";
    impersonate(lpWhale);
    const lpSigner = await ethers.provider.getSigner(lpWhale);
    await fixture.curveLp
      .connect(lpSigner)
      .transfer(fixture.yvstecrv.address, amount);
  }

  before(async () => {
    // snapshot initial state
    await createSnapshot(provider);

    // load all related contracts

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
    fixture = await loadStethPoolMainnetFixture(users[1].address);

    const stethHolderAddress = "0x62e41b1185023bcc14a465d350e1dde341557925";
    impersonate(stethHolderAddress);
    stethSigner = await ethers.provider.getSigner(stethHolderAddress);
    await fixture.steth
      .connect(users[1].user)
      .approve(fixture.zapper.address, ethers.constants.MaxUint256);
  });
  describe("rescueTokens", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should correctly rescue ETH", async () => {
      await users[2].user.sendTransaction({
        to: fixture.zapper.address,
        value: ethers.utils.parseEther("2"),
      });
      const initialBalance = await provider.getBalance(users[1].address);
      // send 2 eth to the zapper and attempt to rescue it
      await fixture.zapper
        .connect(users[1].user)
        .rescueTokens(
          "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
          ethers.utils.parseEther("2")
        );
      const finalBalance = await provider.getBalance(users[1].address);
      expect(finalBalance).to.be.at.least(
        initialBalance.add(ethers.utils.parseEther("1.9"))
      );
    });
    it("should correctly rescue ERC20", async () => {
      const inputValue = ethers.utils.parseEther("10");
      await fixture.steth
        .connect(stethSigner)
        .transfer(fixture.zapper.address, inputValue);
      const initialBalance = await fixture.steth.balanceOf(users[1].address);
      // send 2 eth to the zapper and attempt to rescue it
      await fixture.zapper
        .connect(users[1].user)
        .rescueTokens(fixture.steth.address, inputValue);
      const finalBalance = await fixture.steth.balanceOf(users[1].address);
      expect(finalBalance).to.be.at.least(initialBalance.add(10));
    });
  });
  describe("zapEthIn", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should fail if contract is frozen", async () => {
      await fixture.zapper.connect(users[1].user).setIsFrozen(true);
      const inputValue = ethers.utils.parseEther("1");
      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapEthIn(inputValue, 1e10, fixture.position.address, inputValue, {
            value: inputValue,
          })
      ).to.be.revertedWith("Contract frozen");
    });
    it("should fail with incorrect amount", async () => {
      const inputValue = ethers.utils.parseEther("1");
      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapEthIn(inputValue, 1e10, fixture.position.address, inputValue, {
            value: inputValue.add(1),
          })
      ).to.be.revertedWith("Incorrect amount provided");
    });
    it("should fail if insufficient tokens were minted", async () => {
      const inputValue = ethers.utils.parseEther("10");
      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapEthIn(inputValue, 1e10, fixture.position.address, inputValue, {
            value: inputValue,
          })
      ).to.be.revertedWith("Not enough PT minted");
    });
    it("should correctly convert ETH to yvsteCRV principal/interest tokens using zapEthIn", async () => {
      const inputValue = 10000000000;
      let trancheValue = await fixture.tranche.balanceOf(users[1].address);
      expect(trancheValue).to.equal(0);
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 1, {
          value: inputValue,
        });
      trancheValue = await fixture.tranche.balanceOf(users[1].address);
      expect(trancheValue).to.be.at.least(1);
    });
  });
  describe("zapStethIn", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should fail with incorrect amount", async () => {
      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapStEthIn(0, 1e10, fixture.position.address, 500)
      ).to.be.revertedWith("0 stETH");
    });
    it("should fail if insufficient tokens were minted", async () => {
      const inputValue = ethers.utils.parseEther("10");
      await fixture.steth
        .connect(stethSigner)
        .transfer(users[1].address, inputValue);
      const stethValue = await fixture.steth.balanceOf(users[1].address);

      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapStEthIn(stethValue, 1e10, fixture.position.address, stethValue)
      ).to.be.revertedWith("Not enough PT minted");
    });
    it("should correctly convert stETH to yvsteCRV principal/interest tokens using zapStEthIn", async () => {
      const inputValue = ethers.utils.parseEther("1");
      await fixture.steth
        .connect(stethSigner)
        .transfer(users[1].address, inputValue);
      const stethValue = await fixture.steth.balanceOf(users[1].address);

      let trancheValue = await fixture.tranche.balanceOf(users[1].address);
      expect(trancheValue).to.equal(0);
      await fixture.zapper
        .connect(users[1].user)
        .zapStEthIn(stethValue, 1e10, fixture.position.address, 1);
      trancheValue = await fixture.tranche.balanceOf(users[1].address);
      expect(trancheValue).to.be.at.least(1);
    });
  });
  describe("zapOut - stETH - principal", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should fail with incorrect expected output", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 1, {
          value: inputValue,
        });
      const trancheValue = await fixture.tranche.balanceOf(users[1].address);
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);
      await fixture.tranche.hitSpeedbump();
      advanceTime(provider, 1e8);

      await fixture.tranche
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValue);
      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapOutStEth(
            1e10,
            fixture.position.address,
            trancheValue,
            0,
            inputValue.mul(2)
          )
      ).to.be.revertedWith("Insufficient Output");
    });
    it("should correctly convert principal tokens to ETH using zapOutPrincipalEth", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 1, {
          value: inputValue,
        });
      const trancheValue = await fixture.tranche.balanceOf(users[1].address);
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);
      await fixture.tranche.hitSpeedbump();
      advanceTime(provider, 1e8);

      await fixture.tranche
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValue);
      const initialBalance = await fixture.steth.balanceOf(users[1].address);
      await fixture.zapper
        .connect(users[1].user)
        .zapOutStEth(1e10, fixture.position.address, trancheValue, 0, 0);
      const finalBalance = await fixture.steth.balanceOf(users[1].address);

      expect(finalBalance).to.be.at.least(
        initialBalance.add(ethers.utils.parseEther("1.9"))
      );
    });
  });
  describe("zapOut - ETH - principal", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should fail with incorrect expected output", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 1, {
          value: inputValue,
        });
      const trancheValue = await fixture.tranche.balanceOf(users[1].address);
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);
      await fixture.tranche.hitSpeedbump();
      advanceTime(provider, 1e8);

      await fixture.tranche
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValue);
      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapOutEth(
            1e10,
            fixture.position.address,
            trancheValue,
            0,
            inputValue.mul(2)
          )
      ).to.be.revertedWith("Insufficient Output");
    });
    it("should correctly convert principal tokens to ETH using zapOutPrincipalEth", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 500, {
          value: inputValue,
        });
      const trancheValue = await fixture.tranche.balanceOf(users[1].address);
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);
      await fixture.tranche.hitSpeedbump();
      advanceTime(provider, 1e8);

      const initialBalance = await provider.getBalance(users[1].address);
      await fixture.tranche
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValue);

      await fixture.zapper
        .connect(users[1].user)
        .zapOutEth(1e10, fixture.position.address, trancheValue, 0, 0);
      const finalBalance = await provider.getBalance(users[1].address);

      expect(finalBalance).to.be.at.least(
        initialBalance.add(ethers.utils.parseEther("1.9"))
      );
    });
  });
  describe("zapOut - stETH - interest", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should fail with incorrect expected output", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 500, {
          value: inputValue,
        });

      const trancheValue = await fixture.interestToken.balanceOf(
        users[1].address
      );
      await fixture.interestToken.connect(users[1].user);

      yearnInterestSim(ethers.utils.parseEther("40"));
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);

      await fixture.interestToken
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValue);

      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapOutStEth(
            1e10,
            fixture.position.address,
            0,
            trancheValue,
            inputValue
          )
      ).to.be.revertedWith("Insufficient Output");
    });
    it("should correctly convert interest tokens to stETH using zapOutStEth", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 500, {
          value: inputValue,
        });

      const trancheValue = await fixture.interestToken.balanceOf(
        users[1].address
      );
      await fixture.interestToken.connect(users[1].user);

      yearnInterestSim(ethers.utils.parseEther("40"));
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);

      await fixture.interestToken
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValue);

      const initialBalance = await fixture.steth.balanceOf(users[1].address);
      await fixture.zapper
        .connect(users[1].user)
        .zapOutStEth(1e10, fixture.position.address, 0, trancheValue, 0);
      const finalBalance = await fixture.steth.balanceOf(users[1].address);

      const ytBalance = await fixture.interestToken
        .connect(users[1].user)
        .balanceOf(users[1].address);

      expect(ytBalance).to.be.equal(0);
      expect(finalBalance).to.be.least(initialBalance);
    });
  });
  describe("zapOut - ETH - interest", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should fail with incorrect expected output", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 500, {
          value: inputValue,
        });

      const trancheValue = await fixture.interestToken.balanceOf(
        users[1].address
      );
      await fixture.interestToken.connect(users[1].user);

      yearnInterestSim(ethers.utils.parseEther("40"));
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);

      await fixture.interestToken
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValue);

      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapOutEth(
            1e10,
            fixture.position.address,
            0,
            trancheValue,
            inputValue
          )
      ).to.be.revertedWith("Insufficient Output");
    });
    it("should correctly convert interest tokens to ETH using zapOutEth", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 500, {
          value: inputValue,
        });

      const trancheValue = await fixture.interestToken.balanceOf(
        users[1].address
      );
      await fixture.interestToken.connect(users[1].user);

      yearnInterestSim(ethers.utils.parseEther("40"));
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);

      await fixture.interestToken
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValue);

      const initialBalance = await provider.getBalance(users[1].address);
      await fixture.zapper
        .connect(users[1].user)
        .zapOutEth(1e10, fixture.position.address, 0, trancheValue, 0);
      const finalBalance = await provider.getBalance(users[1].address);

      const ytBalance = await fixture.interestToken
        .connect(users[1].user)
        .balanceOf(users[1].address);

      expect(ytBalance).to.be.equal(0);
      expect(finalBalance).to.be.least(initialBalance);
    });
  });
  describe("zapOut - stETH - principal + interest", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should fail with incorrect expected output", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 500, {
          value: inputValue,
        });

      const trancheValueInterest = await fixture.interestToken.balanceOf(
        users[1].address
      );
      const trancheValuePrincipal = await fixture.tranche.balanceOf(
        users[1].address
      );

      await fixture.interestToken.connect(users[1].user);

      yearnInterestSim(ethers.utils.parseEther("40"));
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);

      await fixture.interestToken
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValueInterest);
      await fixture.tranche
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValuePrincipal);
      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapOutStEth(
            1e10,
            fixture.position.address,
            trancheValuePrincipal,
            trancheValueInterest,
            inputValue.mul(2)
          )
      ).to.be.revertedWith("Insufficient Output");
    });
    it("should correctly convert principal and interest tokens to stETH using zapOutStEth", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 500, {
          value: inputValue,
        });

      const trancheValueInterest = await fixture.interestToken.balanceOf(
        users[1].address
      );
      const trancheValuePrincipal = await fixture.tranche.balanceOf(
        users[1].address
      );

      await fixture.interestToken.connect(users[1].user);

      yearnInterestSim(ethers.utils.parseEther("40"));
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);

      await fixture.interestToken
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValueInterest);
      await fixture.tranche
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValuePrincipal);
      const initialBalance = await fixture.steth.balanceOf(users[1].address);
      await fixture.zapper
        .connect(users[1].user)
        .zapOutStEth(
          1e10,
          fixture.position.address,
          trancheValuePrincipal,
          trancheValueInterest,
          0
        );

      const finalBalance = await fixture.steth.balanceOf(users[1].address);

      const ytBalance = await fixture.interestToken
        .connect(users[1].user)
        .balanceOf(users[1].address);

      expect(ytBalance).to.be.equal(0);
      expect(finalBalance).to.be.least(initialBalance);
    });
  });
  describe("zapOut - ETH - principal + interest", () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });
    afterEach(async () => {
      await restoreSnapshot(provider);
    });
    it("should fail with incorrect expected output", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 500, {
          value: inputValue,
        });

      const trancheValueInterest = await fixture.interestToken.balanceOf(
        users[1].address
      );
      const trancheValuePrincipal = await fixture.tranche.balanceOf(
        users[1].address
      );

      await fixture.interestToken.connect(users[1].user);

      yearnInterestSim(ethers.utils.parseEther("40"));
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);

      await fixture.interestToken
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValueInterest);
      await fixture.tranche
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValuePrincipal);
      await expect(
        fixture.zapper
          .connect(users[1].user)
          .zapOutEth(
            1e10,
            fixture.position.address,
            trancheValuePrincipal,
            trancheValueInterest,
            inputValue.mul(2)
          )
      ).to.be.revertedWith("Insufficient Output");
    });
    it("should correctly convert principal and interest tokens to ETH using zapOutStEth", async () => {
      const inputValue = ethers.utils.parseEther("2");
      await fixture.zapper
        .connect(users[1].user)
        .zapEthIn(inputValue, 1e10, fixture.position.address, 500, {
          value: inputValue,
        });

      const trancheValueInterest = await fixture.interestToken.balanceOf(
        users[1].address
      );
      const trancheValuePrincipal = await fixture.tranche.balanceOf(
        users[1].address
      );

      await fixture.interestToken.connect(users[1].user);

      yearnInterestSim(ethers.utils.parseEther("40"));
      // fast forward so we can withdraw
      advanceTime(provider, 1e10);

      await fixture.interestToken
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValueInterest);
      await fixture.tranche
        .connect(users[1].user)
        .approve(fixture.zapper.address, trancheValuePrincipal);
      const initialBalance = await provider.getBalance(users[1].address);
      await fixture.zapper
        .connect(users[1].user)
        .zapOutEth(
          1e10,
          fixture.position.address,
          trancheValuePrincipal,
          trancheValueInterest,
          0
        );

      const finalBalance = await provider.getBalance(users[1].address);

      const ytBalance = await fixture.interestToken
        .connect(users[1].user)
        .balanceOf(users[1].address);

      expect(ytBalance).to.be.equal(0);
      expect(finalBalance).to.be.least(initialBalance);
    });
  });
});
