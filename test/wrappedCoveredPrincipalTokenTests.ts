import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, waffle } from "hardhat";
import { WrappedCoveredPrincipalTokenFactory } from "typechain/WrappedCoveredPrincipalTokenFactory";
import { WrappedCoveredPrincipalToken } from "typechain/WrappedCoveredPrincipalToken";
import { WrappedCoveredPrincipalTokenFactory__factory } from "typechain/factories/WrappedCoveredPrincipalTokenFactory__factory";
import { WrappedCoveredPrincipalToken__factory } from "typechain/factories/WrappedCoveredPrincipalToken__factory";
import { TestERC20 } from "typechain/TestERC20";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {
  deployUsdc,
  loadTestTrancheFixtureWithBaseAsset,
  TrancheTestFixtureWithBaseAsset,
} from "./helpers/deployer";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { advanceTime, getCurrentTimestamp } from "./helpers/time";
import { getPermitSignature } from "./helpers/signatures";
import { ERC20Permit } from "typechain/ERC20Permit";
import data from "../artifacts/contracts/Tranche.sol/Tranche.json";

const { provider } = waffle;

const initialBalance = ethers.BigNumber.from("2000000"); // 2e9

describe("WrappedCoveredPrincipalToken", function () {
  let fixture: TrancheTestFixtureWithBaseAsset;
  let factory: WrappedCoveredPrincipalTokenFactory;
  let coveredToken: WrappedCoveredPrincipalToken;
  let signers: SignerWithAddress[];
  let baseToken: TestERC20;
  let coveredOwner: string;
  let user1: Signer;
  let user2: Signer;
  let user1Address: string;
  let user2Address: string;
  let expiration: number;

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();
    expiration = (await getCurrentTimestamp(provider)) + 10000;
    const factoryDeployer = new WrappedCoveredPrincipalTokenFactory__factory(
      signers[0]
    );
    const coveredTokenDeployer = new WrappedCoveredPrincipalToken__factory(
      signers[0]
    );

    const tempUsdc = await deployUsdc(
      signers[0],
      (await signers[0].getAddress()) as string
    );
    // load all related contracts
    fixture = await loadTestTrancheFixtureWithBaseAsset(tempUsdc, expiration);

    coveredOwner = signers[1].address;
    baseToken = fixture.usdc;
    const bytecodehash = ethers.utils.solidityKeccak256(
      ["bytes"],
      [data.bytecode]
    );
    factory = await factoryDeployer.deploy(
      fixture.trancheFactory.address,
      bytecodehash
    );
    await factory.create(baseToken.address, coveredOwner);
    coveredToken = coveredTokenDeployer.attach(
      (await factory.allWrappedCoveredPrincipalTokens())[0]
    );

    [user1, user2] = await ethers.getSigners();
    user1Address = await user1.getAddress();
    user2Address = await user2.getAddress();

    // Mint for the users
    await fixture.usdc.connect(user1).setBalance(user1Address, initialBalance);
    await fixture.usdc.connect(user2).setBalance(user2Address, initialBalance);
    // Set approvals on the tranche
    await fixture.usdc.connect(user1).approve(fixture.tranche.address, 2e10);
    await fixture.usdc.connect(user2).approve(fixture.tranche.address, 2e10);
  });
  after(async () => {
    await restoreSnapshot(provider);
  });

  describe("Validate Constructor", async () => {
    it("Should initialize correctly", async () => {
      const adminRole = await coveredToken.ADMIN_ROLE();
      const reclaimRole = await coveredToken.RECLAIM_ROLE();
      expect(await coveredToken.hasRole(adminRole, coveredOwner)).to.true;
      expect(await coveredToken.getRoleAdmin(adminRole)).to.be.equal(adminRole);
      expect(await coveredToken.getRoleAdmin(reclaimRole)).to.be.equal(
        adminRole
      );
      expect(await coveredToken.name()).to.equal(
        "WrappedtUSDCCovered Principal"
      );
      expect(await coveredToken.symbol()).to.equal("WtUSDC");
      expect(await coveredToken.baseToken()).to.equal(baseToken.address);
    });
  });

  describe("Tranche mgt", async () => {
    const tokenToMint = ethers.BigNumber.from("2000000000000000000");

    before(async () => {
      await createSnapshot(provider);
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, user1Address);
      await fixture.tranche
        .connect(user2)
        .deposit(initialBalance, user2Address);

      // check for correct Interest Token balance
      expect(await fixture.interestToken.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.interestToken.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      // check for correct Principal Token balance
      expect(await fixture.tranche.balanceOf(user1Address)).to.equal(
        initialBalance
      );
      expect(await fixture.tranche.balanceOf(user2Address)).to.equal(
        initialBalance
      );

      await coveredToken
        .connect(signers[1])
        .addWrappedPosition(fixture.positionStub.address);
    });

    after(async () => {
      await restoreSnapshot(provider);
    });

    it("should fail to add wrapped position because msg.sender is not the owner", async () => {
      const tx = coveredToken
        .connect(signers[2])
        .addWrappedPosition(signers[2].address);
      await expect(tx).to.be.revertedWith(
        "AccessControl: account 0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc is missing role 0x41444d494e5f524f4c4500000000000000000000000000000000000000000000"
      );
    });

    it("should fail to add wrapped position because baseToken doesn't match", async () => {
      const tokenDeployer = new TestERC20__factory(signers[0]);
      const token = await tokenDeployer.deploy("Test1", "TOP", 18);
      const fakeWrappedPosition = (
        await loadTestTrancheFixtureWithBaseAsset(token, 1e10)
      ).positionStub;
      const tx = coveredToken
        .connect(signers[1])
        .addWrappedPosition(fakeWrappedPosition.address);
      await expect(tx).to.be.revertedWith("WFP:INVALID_WP");
    });

    // it("should successfully add the wrapped position", async () => {
    //   await coveredToken
    //     .connect(signers[1])
    //     .addWrappedPosition(fixture.positionStub.address);
    //   expect((await coveredToken.allWrappedPositions()).length).to.equal(1);
    //   expect(await coveredToken.isAllowedWp(fixture.positionStub.address)).to.equal(true);
    // });

    it("should fail to add wrapped position because it is already added", async () => {
      const tx = coveredToken
        .connect(signers[1])
        .addWrappedPosition(fixture.positionStub.address);
      await expect(tx).to.be.revertedWith("WFP:ALREADY_EXISTS");
    });

    it("should fail to mint the un allowed wrapped position", async () => {
      const tokenDeployer = new TestERC20__factory(signers[0]);
      const token = await tokenDeployer.deploy("Test1", "TOP", 18);
      const fakeWrappedPosition = (
        await loadTestTrancheFixtureWithBaseAsset(token, 1e10)
      ).positionStub;

      const tx = coveredToken
        .connect(user1)
        .mint(tokenToMint, 1e10, fakeWrappedPosition.address, {
          spender: "0x0000000000000000000000000000000000000000",
          value: 0,
          deadline: 0,
          v: 0,
          r: ethers.utils.hexZeroPad("0x1f", 32),
          s: ethers.utils.hexZeroPad("0x1f", 32),
        });
      await expect(tx).to.be.revertedWith("WFP:INVALID_WP");
    });

    it("should failed to mint the wrapped covered token because position is not expired yet", async () => {
      const tx = coveredToken
        .connect(user1)
        .mint(tokenToMint, expiration, fixture.positionStub.address, {
          spender: "0x0000000000000000000000000000000000000000",
          value: 0,
          deadline: 0,
          v: 0,
          r: ethers.utils.hexZeroPad("0x1f", 32),
          s: ethers.utils.hexZeroPad("0x1f", 32),
        });
      await expect(tx).to.be.revertedWith("WFP:POSITION_NOT_EXPIRED");
    });

    describe("Tests after time advance", async () => {
      before(async () => {
        const expirationTime = (await fixture.tranche.unlockTimestamp()).add(1);
        advanceTime(provider, expirationTime.toNumber());
      });

      it("should failed to mint the wrapped covered token because allowance not provided", async () => {
        const tx = coveredToken
          .connect(user1)
          .mint(tokenToMint, expiration, fixture.positionStub.address, {
            spender: "0x0000000000000000000000000000000000000000",
            value: 0,
            deadline: 0,
            v: 0,
            r: ethers.utils.hexZeroPad("0x1f", 32),
            s: ethers.utils.hexZeroPad("0x1f", 32),
          });
        await expect(tx).to.be.revertedWith("ERC20: insufficient-allowance");
      });

      it("should successfully mint the wrapped covered token", async () => {
        await fixture.tranche
          .connect(user1)
          .approve(coveredToken.address, initialBalance);
        await coveredToken
          .connect(user1)
          .mint(tokenToMint, expiration, fixture.positionStub.address, {
            spender: "0x0000000000000000000000000000000000000000",
            value: 0,
            deadline: 0,
            v: 0,
            r: ethers.utils.hexZeroPad("0x1f", 32),
            s: ethers.utils.hexZeroPad("0x1f", 32),
          });
        expect(await coveredToken.balanceOf(user1Address)).to.equal(
          tokenToMint
        );
        expect(await fixture.tranche.balanceOf(user1Address)).to.equal(0);
      });

      it("should failed to mint the wrapped covered token as allowance not provide because of invalid permit data", async () => {
        const token = fixture.tranche as ERC20Permit;
        const sig = await getPermitSignature(
          token,
          user1Address,
          coveredToken.address,
          initialBalance,
          "1"
        );
        const tx = coveredToken
          .connect(user2)
          .mint(tokenToMint, expiration, fixture.positionStub.address, {
            spender: coveredToken.address,
            value: initialBalance,
            deadline: ethers.constants.MaxUint256,
            v: sig.v,
            r: sig.r,
            s: sig.s,
          });
        await expect(tx).to.be.revertedWith("ERC20: invalid-permit");
      });

      it("should successfully mint the wrapped covered token using permit data", async () => {
        const token = fixture.tranche as ERC20Permit;
        const sig = await getPermitSignature(
          token,
          user2Address,
          coveredToken.address,
          initialBalance,
          "1"
        );
        await coveredToken
          .connect(user2)
          .mint(tokenToMint, expiration, fixture.positionStub.address, {
            spender: coveredToken.address,
            value: initialBalance,
            deadline: ethers.constants.MaxUint256,
            v: sig.v,
            r: sig.r,
            s: sig.s,
          });
        expect(await coveredToken.balanceOf(user2Address)).to.equal(
          tokenToMint
        );
        expect(await fixture.tranche.balanceOf(user2Address)).to.equal(0);
      });
    });

    it("should verify the getters output", async () => {
      expect(await coveredToken.isAllowedWp(fixture.positionStub.address)).to.be
        .true;
      expect((await coveredToken.allWrappedPositions()).length).to.be.equal(1);
    });
  });
});
