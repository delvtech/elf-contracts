import { BigNumber, BigNumberish } from "ethers";
import {
  defaultAbiCoder,
  keccak256,
  solidityPack,
  toUtf8Bytes,
} from "ethers/lib/utils";
import { ethers } from "hardhat";
import { ERC20Permit } from "typechain/ERC20Permit";

export const PERMIT_TYPEHASH = keccak256(
  toUtf8Bytes(
    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
  )
);

// TODO tokenName and tokenAddress unnecessary?
export function getDigest(
  _: string,
  domainSeparator: string,
  __: string,
  owner: string,
  spender: string,
  value: BigNumberish,
  nonce: BigNumberish,
  deadline: BigNumberish
) {
  return keccak256(
    solidityPack(
      ["bytes1", "bytes1", "bytes32", "bytes32"],
      [
        "0x19",
        "0x01",
        domainSeparator,
        keccak256(
          defaultAbiCoder.encode(
            ["bytes32", "address", "address", "uint256", "uint256", "uint256"],
            [PERMIT_TYPEHASH, owner, spender, value, nonce, deadline]
          )
        ),
      ]
    )
  );
}

export async function getPermitSignature(
  token: ERC20Permit,
  sourceAddr: string,
  spenderAddr: string,
  spenderAmount: BigNumberish,
  version: string,
  // If we are using a fork, the DOMAIN_SEPARATOR would sometimes be constructed
  // using the chainId of mainnet causing discrepancy
  chainId?: number
) {
  // Load a json rpc signer
  const signer = ethers.provider.getSigner(sourceAddr);

  const name = await token.name();
  const _chainId = chainId ?? (await signer.getChainId());

  const domain = {
    name: name,
    version: version,
    chainId: _chainId,
    verifyingContract: token.address,
  };

  const types = {
    Permit: [
      {
        name: "owner",
        type: "address",
      },
      {
        name: "spender",
        type: "address",
      },
      {
        name: "value",
        type: "uint256",
      },
      {
        name: "nonce",
        type: "uint256",
      },
      {
        name: "deadline",
        type: "uint256",
      },
    ],
  };

  const nonce = await token.nonces(sourceAddr);

  const data = {
    owner: sourceAddr,
    spender: spenderAddr,
    value: spenderAmount,
    nonce: nonce,
    deadline: ethers.constants.MaxUint256,
  };

  const sigStringPromise = signer._signTypedData(domain, types, data);
  return sigStringPromise.then((value: string) => {
    return parseSigString(value);
  });
}

// Turns a 65 digit hex string prefixed by 0x into r, s, and v
function parseSigString(signature: string) {
  return {
    r: signature.slice(0, 66),
    s: "0x" + signature.slice(66, 130),
    v: BigNumber.from("0x" + signature.slice(130)).toNumber(),
  };
}

export function getFunctionSignature(sig: string) {
  return ethers.utils.Interface.getSighash(
    ethers.utils.FunctionFragment.from(sig)
  );
}
