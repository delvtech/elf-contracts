import { LedgerSigner } from "@ethersproject/hardware-wallets";
import { ethers, providers } from "ethers";
import hre from "hardhat";

// Smart contract imports
import { TrancheFactory__factory } from "typechain/factories/TrancheFactory__factory";
import { InterestTokenFactory__factory } from "typechain/factories/InterestTokenFactory__factory";
import { YVaultAssetProxy__factory } from "typechain/factories/YVaultAssetProxy__factory";
import { WrappedPosition__factory } from "typechain/factories/WrappedPosition__factory";

// An interface to allow us to access the ethers log return
interface LogData {
  event: string;

  // TODO: figure out what this is.
  data: unknown;
}

// A partially extended interface for the post mining transaction receipt
interface PostExecutionTransactionReceipt extends providers.TransactionReceipt {
  events: LogData[];
}

async function main() {
  interface DeploymentData {
    underlyingTokens: { [name: string]: string[] };
    initialTrancheTimestamps: { [name: string]: number[] };
  }

  // TODO - Make this a typed import
  const deploymentData: DeploymentData = {
    // The underlying token data as (token address, yearn vault address)
    underlyingTokens: {
      yUSDC: ["0x", "0x"],
    },
    // A listing of which timestamps we want to deploy Tranches for
    initialTrancheTimestamps: {
      yUSDC: [10],
    },
  };

  interface AssetDeployment {
    wrappedPositionAddress: string;
    trancheAddresses: string[];
  }

  const deploymentResult = {
    interestTokenFactory: "",
    trancheFactory: "",
    elfDeployments: [] as AssetDeployment[],
  };

  // We define a testnet provider and ledger signer
  const provider = ethers.getDefaultProvider("ropsten");
  // There's a weird circular import error in the next line
  // eslint-disable-next-line @typescript-eslint/ban-ts-comment
  // @ts-ignore
  const signer = new LedgerSigner(provider);
  // Deploy the interest token factory
  const interestTokenFactoryFactory = new InterestTokenFactory__factory(signer);
  const interestToken = await interestTokenFactoryFactory.deploy();
  console.log("Interest Token Factory", interestToken.address);
  // Verify the interest token on etherscan
  await verify(interestToken.address, []);
  deploymentResult.interestTokenFactory = interestToken.address;

  // Deploy the tranche factory
  const trancheFactoryFactory = new TrancheFactory__factory(signer);
  const trancheFactory = await trancheFactoryFactory.deploy(
    interestToken.address
  );
  // Verify the tranche factory on etherscan
  await verify(trancheFactory.address, [interestToken.address]);
  deploymentResult.trancheFactory = trancheFactory.address;
  console.log("Tranche Factory", trancheFactory.address);

  const yAssetWPFactory = new YVaultAssetProxy__factory(signer);
  // We now deploy the elf contracts for each of the underlying tokens
  for (const [key, value] of Object.entries(deploymentData.underlyingTokens)) {
    // First we deploy the yearn wrapped position

    const wrappedPosition = await yAssetWPFactory.deploy(
      value[0],
      value[1],
      "Wrapped Position" + key,
      key
    );
    console.log("Wrapped Position", wrappedPosition.address);
    await verify(wrappedPosition.address, [
      value[0],
      value[1],
      "Wrapped Position" + key,
      key,
    ]);
    // Then we deploy each tranche for each end date we want

    const trancheAddresses = [];
    for (const timestamp of deploymentData.initialTrancheTimestamps[key]) {
      // Deploy the tranche for this timestamp
      const txReceipt = (await (
        await trancheFactory.deployTranche(timestamp, wrappedPosition.address)
      ).wait()) as PostExecutionTransactionReceipt;
      const returned = txReceipt.events.filter(
        (event) => event.event == "TrancheCreated"
      );
      const trancheAddress = returned[0].data as string;
      trancheAddresses.push(trancheAddress);
      console.log("Tranche", trancheAddress);
      await verify(trancheAddress, []);
    }

    deploymentResult.elfDeployments.push({
      wrappedPositionAddress: wrappedPosition.address,
      trancheAddresses: trancheAddresses,
    });
  }

  console.log(deploymentResult);
}

async function verify(address: string, constructorArguments: any) {
  await hre.run("verify:verify", {
    address: address,
    constructorArguments: constructorArguments,
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
