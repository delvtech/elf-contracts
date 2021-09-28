import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import chai, { expect } from "chai";
import { BigNumber, BigNumberish, providers, Wallet } from "ethers";
import { ethers, waffle } from "hardhat";
import { setBlock } from "test/helpers/forking";
import {
  ccPoolExitRequest,
  ccPoolJoinRequest,
  weightedPoolJoinRequest,
  weightedPoolExitRequest,
} from "test/helpers/poolHelpers";

import { getCurrentTimestamp, advanceTime } from "test/helpers/time";
import { getPermitSignature, getDigest } from "./helpers/signatures";
import { Vault__factory } from "typechain/factories/Vault__factory";
import { Vault } from "typechain/Vault";
import { MockProvider } from "ethereum-waffle";
import { ecsign } from "ethereumjs-util";
import { defaultAbiCoder } from "ethers/lib/utils";

import { ERC20Permit__factory } from "typechain/factories/ERC20Permit__factory";
import { Tranche__factory } from "typechain/factories/Tranche__factory";
import { Tranche } from "typechain/Tranche";
import { ERC20Permit } from "typechain/ERC20Permit";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { ZapTrancheLp__factory } from "typechain/factories/ZapTrancheLp__factory";
import { ZapTrancheLp } from "typechain/ZapTrancheLp";
import { impersonate, stopImpersonating } from "./helpers/impersonate";

const { provider } = waffle;

describe("zapLp", function () {
  let signers: SignerWithAddress[];
  let walletSigner: providers.JsonRpcSigner;
  let zapLp: ZapTrancheLp;
  let initBlock: number;
  let vault: Vault;
  let trancheBefore: Tranche;
  let trancheAfter: Tranche;
  let trancheBeforePtLp: ERC20Permit;
  let trancheBeforeYtLp: ERC20Permit;
  let trancheAfterPtLp: ERC20Permit;
  let trancheAfterYtLp: ERC20Permit;
  let trancheBeforePtPoolId: string;
  let trancheBeforeYtPoolId: string;
  let trancheAfterPtPoolId: string;
  let trancheAfterYtPoolId: string;

  before(async function () {
    initBlock = await provider.getBlockNumber();
    await createSnapshot(provider);
    // set new fork at new block.
    // NOTE: RESET FORK TO INITIAL BLOCK AFTER THESE TESTS.
    // do not modify test block as dependencies might change
    setBlock(13274899);

    signers = await ethers.getSigners();

    // deploy zapper using mainnet vault address 0xba12222222228d8ba445958a75a0704d566bf2c8
    const zapDeployer = new ZapTrancheLp__factory(signers[0]);

    zapLp = await zapDeployer.deploy(
      "0xba12222222228d8ba445958a75a0704d566bf2c8"
    );
    vault = Vault__factory.connect(
      "0xba12222222228d8ba445958a75a0704d566bf2c8",
      signers[0]
    );
    trancheBefore = Tranche__factory.connect(
      "0x9b44Ed798a10Df31dee52C5256Dcb4754BCf097E",
      signers[0]
    );
    // LPePyvCurveLUSD-28SEP21
    trancheBeforePtLp = ERC20Permit__factory.connect(
      "0xa8d4433badaa1a35506804b43657b0694dea928d",
      signers[0]
    );
    trancheBeforePtPoolId =
      "0xa8d4433badaa1a35506804b43657b0694dea928d00020000000000000000005e";
    // LPeYyvCurveLUSD-28SEP21
    trancheBeforeYtLp = ERC20Permit__factory.connect(
      "0xde620bb8be43ee54d7aa73f8e99a7409fe511084",
      signers[0]
    );
    trancheBeforeYtPoolId =
      "0xde620bb8be43ee54d7aa73f8e99a7409fe51108400020000000000000000005d";
    trancheAfter = Tranche__factory.connect(
      "0xa2b3d083AA1eaa8453BfB477f062A208Ed85cBBF",
      signers[0]
    );
    //  LPePyvCurveLUSD-27DEC21
    trancheAfterPtLp = ERC20Permit__factory.connect(
      "0x893b30574bf183d69413717f30b17062ec9dfd8b",
      signers[0]
    );
    trancheAfterPtPoolId =
      "0x893b30574bf183d69413717f30b17062ec9dfd8b000200000000000000000061";
    //  LPeYyvCurveLUSD-27DEC21
    trancheAfterYtLp = ERC20Permit__factory.connect(
      "0x67f8fcb9d3c463da05de1392efdbb2a87f8599ea",
      signers[0]
    );
    trancheAfterYtPoolId =
      "0x67f8fcb9d3c463da05de1392efdbb2a87f8599ea000200000000000000000060";

    // move first tranche to expiration making PT and YT redeemable
    const target = (await trancheBefore.unlockTimestamp()).toNumber();
    const current = await getCurrentTimestamp(provider);
    await advanceTime(provider, target - current);
    // approve tokens for balancer usage from zapper
    const underlying = await trancheAfter.underlying();
    const yt = await trancheAfter.interestToken();
    await zapLp
      .connect(signers[0])
      .tokenApproval(
        [trancheAfter.address, underlying, yt],
        [vault.address, vault.address, vault.address]
      );
  });

  after(async function () {
    await restoreSnapshot(provider);
    setBlock(initBlock);
  });
  beforeEach(async () => {
    await createSnapshot(provider);
  });
  afterEach(async () => {
    await restoreSnapshot(provider);
  });
  describe("zapTrancheLp", async () => {
    let lpOutPt: BigNumber;
    let lpOutYt: BigNumber;
    let wallet: Wallet;
    async function permitHandler(
      token: ERC20Permit,
      name: string,
      spender: string,
      wallet: Wallet
    ) {
      const domainSeparator = await token.DOMAIN_SEPARATOR();
      // new wallet so nonce should always be 0
      const nonce = 0;
      const digest = getDigest(
        name,
        domainSeparator,
        token.address,
        wallet.address,
        spender,
        ethers.constants.MaxUint256,
        nonce,
        ethers.constants.MaxUint256
      );

      const { v, r, s } = ecsign(
        Buffer.from(digest.slice(2), "hex"),
        Buffer.from(wallet.privateKey.slice(2), "hex")
      );
      // return the permit input with wallet sig
      return {
        tokenContract: token.address,
        who: spender,
        amount: ethers.constants.MaxUint256,
        expiration: ethers.constants.MaxUint256,
        r: r,
        s: s,
        v: v,
      };
    }
    before(async function () {
      // impersonate address 0x3631401a11ba7004d1311e24d177b05ece39b4b3
      // blockNumber: 13274899
      // target lps:
      //    LP Element Principal Token yvCurveLUSD-28SEP2,
      //    LP Element Yield Token yvCurveLUSD-28SEP21
      // holder info:
      //    LP Principal balance: 3,109,882. ~12% of total supply // like 3.2million
      //    LP Yield balance: 507,122. ~21% of total supply
      const target = "0x3631401a11ba7004d1311e24d177b05ece39b4b3";
      lpOutPt = ethers.BigNumber.from(ethers.utils.parseEther("3000000"));
      lpOutYt = ethers.BigNumber.from(ethers.utils.parseEther("500000"));

      // use Wallet instead of Signer because it is easy to get private key needed for permit signing
      const provider: MockProvider = new MockProvider();
      [wallet] = provider.getWallets();
      walletSigner = await ethers.provider.getSigner(wallet.address);
      const targetsigner = await ethers.provider.getSigner(target);

      // fund the wallet
      await signers[0].sendTransaction({
        to: wallet.address,
        value: ethers.utils.parseEther("1.0"),
      });

      // impersonate target to transfer out LP to wallet
      impersonate(target);

      // transfer lp tokens to permit-signing wallet
      await trancheBeforePtLp
        .connect(targetsigner)
        .transfer(wallet.address, lpOutPt);
      await trancheBeforeYtLp
        .connect(targetsigner)
        .transfer(wallet.address, lpOutYt);

      impersonate(wallet.address);
    });
    it("correctly zaps PT only", async () => {
      const ptPermitInput = await permitHandler(
        trancheBeforePtLp,
        "LP Element Principal Token yvCurveLUSD-28SEP21",
        zapLp.address,
        wallet
      );
      const beforePtAssets = await vault.getPoolTokens(trancheBeforePtPoolId);
      const afterPtAssets = await vault.getPoolTokens(trancheAfterPtPoolId);
      const beforeYtAssets = await vault.getPoolTokens(trancheBeforeYtPoolId);
      const afterYtAssets = await vault.getPoolTokens(trancheAfterYtPoolId);
      const ptOutInfoRequest = await ccPoolExitRequest(
        beforePtAssets[0],
        "100000"
      ); // 100k chosen arbitrarily.
      const ptInInfoRequest = await ccPoolJoinRequest(
        afterPtAssets[0],
        "348251"
      );
      const ytOutInfoRequest = await weightedPoolExitRequest(
        1,
        beforeYtAssets[0],
        ["1", "1"],
        ethers.BigNumber.from("1")
      );
      const ytInInfoRequest = await weightedPoolJoinRequest(
        1,
        afterYtAssets[0],
        ["1", "1"]
      );

      const zapInput = {
        toMint: ethers.utils.parseEther("356037"),
        ptOutInfo: {
          poolId: trancheBeforePtPoolId,
          request: ptOutInfoRequest,
        },
        ytOutInfo: {
          poolId: trancheBeforeYtPoolId,
          request: ytOutInfoRequest,
        },
        ptInInfo: {
          lpCheck: 0,
          poolId: trancheAfterPtPoolId,
          request: ptInInfoRequest,
        },
        ytInInfo: {
          lpCheck: 0,
          poolId: trancheAfterYtPoolId,
          request: ytInInfoRequest,
        },
        onlyPrincipal: true,
      };

      const walletAddress = await wallet.getAddress();
      const balanceBefore = await trancheBeforePtLp.balanceOf(walletAddress);

      await zapLp.connect(walletSigner).zapTrancheLp(zapInput, [ptPermitInput]);

      const balanceAfter = await trancheBeforePtLp.balanceOf(walletAddress);
      const balanceDifference = balanceBefore.sub(balanceAfter);
      const finalLpBalance = await trancheAfterPtLp.balanceOf(walletAddress);

      expect(balanceDifference.mul(95).div(100)).to.be.lt(finalLpBalance);
      // check for dusts:
    });
    it("correctly zaps PT and YT", async () => {
      const inputLp = ethers.utils.parseEther("100000");
      const ptPermitInput = await permitHandler(
        trancheBeforePtLp,
        "LP Element Principal Token yvCurveLUSD-28SEP21",
        zapLp.address,
        wallet
      );
      const ytPermitInput = await permitHandler(
        trancheBeforeYtLp,
        "LP Element Yield Token yvCurveLUSD-28SEP21",
        zapLp.address,
        wallet
      );
      const beforePtAssets = await vault.getPoolTokens(trancheBeforePtPoolId);
      const afterPtAssets = await vault.getPoolTokens(trancheAfterPtPoolId);
      const beforeYtAssets = await vault.getPoolTokens(trancheBeforeYtPoolId);
      const afterYtAssets = await vault.getPoolTokens(trancheAfterYtPoolId);
      const ptOutInfoRequest = await ccPoolExitRequest(
        beforePtAssets[0],
        "100000"
      ); // 100k chosen arbitrarily.
      const ptInInfoRequest = await ccPoolJoinRequest(
        afterPtAssets[0],
        "348251"
      );
      const ytOutInfoRequest = await weightedPoolExitRequest(
        18,
        beforeYtAssets[0],
        ["0", "0"],
        inputLp
      );
      const ytInInfoRequest = await weightedPoolJoinRequest(
        18,
        afterYtAssets[0],
        ["356037", "14861"]
      );

      const zapInput = {
        toMint: ethers.utils.parseEther("356037"),
        ptOutInfo: {
          poolId: trancheBeforePtPoolId,
          request: ptOutInfoRequest,
        },
        ytOutInfo: {
          poolId: trancheBeforeYtPoolId,
          request: ytOutInfoRequest,
        },
        ptInInfo: {
          lpCheck: 0,
          poolId: trancheAfterPtPoolId,
          request: ptInInfoRequest,
        },
        ytInInfo: {
          lpCheck: 0,
          poolId: trancheAfterYtPoolId,
          request: ytInInfoRequest,
        },
        onlyPrincipal: false,
      };

      const walletAddress = await wallet.getAddress();

      await zapLp
        .connect(walletSigner)
        .zapTrancheLp(zapInput, [ptPermitInput, ytPermitInput]);

      const finalLpBalance = await trancheAfterYtLp.balanceOf(walletAddress);

      expect(finalLpBalance).to.be.gt(inputLp);
    });
    it("reverts with insufficient pt lp minted", async () => {
      const ptPermitInput = await permitHandler(
        trancheBeforePtLp,
        "LP Element Principal Token yvCurveLUSD-28SEP21",
        zapLp.address,
        wallet
      );
      const beforePtAssets = await vault.getPoolTokens(trancheBeforePtPoolId);
      const afterPtAssets = await vault.getPoolTokens(trancheAfterPtPoolId);
      const beforeYtAssets = await vault.getPoolTokens(trancheBeforeYtPoolId);
      const afterYtAssets = await vault.getPoolTokens(trancheAfterYtPoolId);
      const ptOutInfoRequest = await ccPoolExitRequest(
        beforePtAssets[0],
        "100000"
      ); // 100k chosen arbitrarily.
      const ptInInfoRequest = await ccPoolJoinRequest(
        afterPtAssets[0],
        "348251"
      );
      const ytOutInfoRequest = await weightedPoolExitRequest(
        1,
        beforeYtAssets[0],
        ["1", "1"],
        ethers.BigNumber.from("1")
      );
      const ytInInfoRequest = await weightedPoolJoinRequest(
        1,
        afterYtAssets[0],
        ["1", "1"]
      );

      const zapInput = {
        toMint: ethers.utils.parseEther("356037"),
        ptOutInfo: {
          poolId: trancheBeforePtPoolId,
          request: ptOutInfoRequest,
        },
        ytOutInfo: {
          poolId: trancheBeforeYtPoolId,
          request: ytOutInfoRequest,
        },
        ptInInfo: {
          lpCheck: ethers.utils.parseEther("300000000"),
          poolId: trancheAfterPtPoolId,
          request: ptInInfoRequest,
        },
        ytInInfo: {
          lpCheck: 0,
          poolId: trancheAfterYtPoolId,
          request: ytInInfoRequest,
        },
        onlyPrincipal: true,
      };

      await expect(
        zapLp.connect(walletSigner).zapTrancheLp(zapInput, [ptPermitInput])
      ).to.be.revertedWith("not enough PT LP minted");
    });
    it("reverts with insufficient yt lp minted", async () => {
      const inputLp = ethers.utils.parseEther("100000");
      const ptPermitInput = await permitHandler(
        trancheBeforePtLp,
        "LP Element Principal Token yvCurveLUSD-28SEP21",
        zapLp.address,
        wallet
      );
      const ytPermitInput = await permitHandler(
        trancheBeforeYtLp,
        "LP Element Yield Token yvCurveLUSD-28SEP21",
        zapLp.address,
        wallet
      );
      const beforePtAssets = await vault.getPoolTokens(trancheBeforePtPoolId);
      const afterPtAssets = await vault.getPoolTokens(trancheAfterPtPoolId);
      const beforeYtAssets = await vault.getPoolTokens(trancheBeforeYtPoolId);
      const afterYtAssets = await vault.getPoolTokens(trancheAfterYtPoolId);
      const ptOutInfoRequest = await ccPoolExitRequest(
        beforePtAssets[0],
        "100000"
      ); // 100k chosen arbitrarily.
      const ptInInfoRequest = await ccPoolJoinRequest(
        afterPtAssets[0],
        "348251"
      );
      const ytOutInfoRequest = await weightedPoolExitRequest(
        18,
        beforeYtAssets[0],
        ["0", "0"],
        inputLp
      );
      const ytInInfoRequest = await weightedPoolJoinRequest(
        18,
        afterYtAssets[0],
        ["356037", "14861"]
      );

      const zapInput = {
        toMint: ethers.utils.parseEther("356037"),
        ptOutInfo: {
          poolId: trancheBeforePtPoolId,
          request: ptOutInfoRequest,
        },
        ytOutInfo: {
          poolId: trancheBeforeYtPoolId,
          request: ytOutInfoRequest,
        },
        ptInInfo: {
          lpCheck: 0,
          poolId: trancheAfterPtPoolId,
          request: ptInInfoRequest,
        },
        ytInInfo: {
          lpCheck: ethers.utils.parseEther("300000000"),
          poolId: trancheAfterYtPoolId,
          request: ytInInfoRequest,
        },
        onlyPrincipal: false,
      };

      await expect(
        zapLp
          .connect(walletSigner)
          .zapTrancheLp(zapInput, [ptPermitInput, ytPermitInput])
      ).to.be.revertedWith("not enough YT LP minted");
    });
  });
});
