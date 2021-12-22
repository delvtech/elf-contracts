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
import { loadTestTrancheFixture, TrancheTestFixture } from "./helpers/deployer";
import { TestTranche__factory } from "typechain/factories/TestTranche__factory";
import { TestERC20__factory } from "typechain/factories/TestERC20__factory";
import { advanceTime } from "./helpers/time";
import { getPermitSignature } from "./helpers/signatures";
import { ERC20Permit } from "typechain/ERC20Permit";

const { provider } = waffle;

const initialBalance = ethers.BigNumber.from("2000000"); // 2e9

describe("WrappedCoveredPrincipalToken", function () {
  let fixture: TrancheTestFixture;
  let factory: WrappedCoveredPrincipalTokenFactory;
  let coveredToken: WrappedCoveredPrincipalToken;
  let signers: SignerWithAddress[];
  let baseToken: TestERC20;
  let coveredOwner: string;
  let user1: Signer;
  let user2: Signer;
  let user1Address: string;
  let user2Address: string;

  before(async function () {
    await createSnapshot(provider);
    signers = await ethers.getSigners();
    const factoryDeployer = new WrappedCoveredPrincipalTokenFactory__factory(
      signers[0]
    );
    const coveredTokenDeployer = new WrappedCoveredPrincipalToken__factory(
      signers[0]
    );

    // load all related contracts
    fixture = await loadTestTrancheFixture();

    coveredOwner = signers[1].address;
    baseToken = fixture.usdc;
    factory = await factoryDeployer.deploy(signers[0].address);
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
      expect(await coveredToken.owner()).to.equal(coveredOwner);
      expect(await coveredToken.isAuthorized(coveredOwner)).to.true;
      expect(await coveredToken.name()).to.equal(
        "WrappedTESTCovered Principal"
      );
      expect(await coveredToken.symbol()).to.equal("ep:WTEST");
      expect(await coveredToken.baseToken()).to.equal(baseToken.address);
    });
  });

  describe("Tranche mgt", async () => {
    const tokenToMint = ethers.BigNumber.from("2000000000000000000");

    before(async () => {
      await createSnapshot(provider);
      await fixture.tranche
        .connect(user1)
        .deposit(initialBalance, await user1.getAddress());
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
    });

    after(async () => {
      await restoreSnapshot(provider);
    });

    it("should fail to add tranche because msg.sender is not the owner", async () => {
      const tx = coveredToken
        .connect(signers[2])
        .addTranche(fixture.tranche.address);
      await expect(tx).to.be.revertedWith("Sender not owner");
    });

    it("should fail to add tranche because baseToken doesn't match", async () => {
      const trancheDeployer = new TestTranche__factory(signers[0]);
      const tokenDeployer = new TestERC20__factory(signers[0]);
      const token = await tokenDeployer.deploy("Test1", "TOP", 18);
      const fakeTranche = await trancheDeployer.deploy(token.address, 478);
      const tx = coveredToken
        .connect(signers[1])
        .addTranche(fakeTranche.address);
      await expect(tx).to.be.revertedWith("WFP:INVALID_TRANCHE");
    });

    it("should successfully add the tranche", async () => {
      await coveredToken
        .connect(signers[1])
        .addTranche(fixture.tranche.address);
      expect((await coveredToken.allTranches()).length).to.equal(1);
    });

    it("should fail to add tranche because tranche is already added", async () => {
      const tx = coveredToken
        .connect(signers[1])
        .addTranche(fixture.tranche.address);
      await expect(tx).to.be.revertedWith("WFP:ALREADY_EXISTS");
    });

    it("should fail to mint the un allowed tranche", async () => {
      const trancheDeployer = new TestTranche__factory(signers[0]);
      const tokenDeployer = new TestERC20__factory(signers[0]);
      const token = await tokenDeployer.deploy("Test1", "TOP", 18);
      const fakeTranche = await trancheDeployer.deploy(token.address, 478);

      const tx = coveredToken
        .connect(user1)
        .mint(tokenToMint, fakeTranche.address, {
          spender: "0x0000000000000000000000000000000000000000",
          value: 0,
          deadline: 0,
          v: 0,
          r: ethers.utils.hexZeroPad("0x1f", 32),
          s: ethers.utils.hexZeroPad("0x1f", 32),
        });
      await expect(tx).to.be.revertedWith("WFP:INVALID_TRANCHE");
    });

    it("should failed to mint the wrapped covered token because position is not expired yet", async () => {
      const tx = coveredToken
        .connect(user1)
        .mint(tokenToMint, fixture.tranche.address, {
          spender: "0x0000000000000000000000000000000000000000",
          value: 0,
          deadline: 0,
          v: 0,
          r: ethers.utils.hexZeroPad("0x1f", 32),
          s: ethers.utils.hexZeroPad("0x1f", 32),
        });
      await expect(tx).to.be.revertedWith("WFP:POSITION_NOT_EXPIRED");
    });

    it("should failed to mint the wrapped covered token because allowance not provided", async () => {
      const expirationTime = (await fixture.tranche.unlockTimestamp()).add(1);
      advanceTime(provider, expirationTime.toNumber());
      const tx = coveredToken
        .connect(user1)
        .mint(tokenToMint, fixture.tranche.address, {
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
        .mint(tokenToMint, fixture.tranche.address, {
          spender: "0x0000000000000000000000000000000000000000",
          value: 0,
          deadline: 0,
          v: 0,
          r: ethers.utils.hexZeroPad("0x1f", 32),
          s: ethers.utils.hexZeroPad("0x1f", 32),
        });
      expect(await coveredToken.balanceOf(user1Address)).to.equal(tokenToMint);
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
        .mint(tokenToMint, fixture.tranche.address, {
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
        .mint(tokenToMint, fixture.tranche.address, {
          spender: coveredToken.address,
          value: initialBalance,
          deadline: ethers.constants.MaxUint256,
          v: sig.v,
          r: sig.r,
          s: sig.s,
        });
      expect(await coveredToken.balanceOf(user2Address)).to.equal(tokenToMint);
      expect(await fixture.tranche.balanceOf(user2Address)).to.equal(0);
    });

    it("should verify the getters output", async () => {
      expect(await coveredToken.isAllowedTranche(fixture.tranche.address)).to.be
        .true;
      expect((await coveredToken.allTranches()).length).to.be.equal(1);
      expect(await coveredToken.getPrice(fixture.tranche.address)).to.equal(
        ethers.BigNumber.from("1")
      );
    });
  });
});
