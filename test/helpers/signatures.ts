import {
  TypedDataDomain,
  TypedDataField,
  TypedDataSigner,
} from "@ethersproject/abstract-signer";
import { BigNumber, BigNumberish, Signer } from "ethers";
import {
  defaultAbiCoder,
  keccak256,
  solidityPack,
  toUtf8Bytes,
} from "ethers/lib/utils";
import { ethers } from "hardhat";
import { ERC20Permit } from "typechain/ERC20Permit";
import { PermitDataStruct } from "typechain/ZapCurveTokenToPrincipalToken";

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
  version: string
) {
  // Load a json rpc signer
  const signer = ethers.provider.getSigner(sourceAddr);

  const name = await token.name();
  console.log(name);
  const chainId = await signer.getChainId();

  console.log(chainId);
  const domain = {
    name: name,
    version: version,
    chainId: chainId,
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

// // Taken from frontend
// export interface PermitCallData {
//   tokenContract: string;
//   who: string;
//   amount: BigNumberish;
//   expiration: BigNumberish;
//   r: BytesLike;
//   s: BytesLike;
//   v: BigNumberish;
// }

// Uses a default infinite permit expiration time
export async function fetchPermitData(
  signer: Signer,
  token: ERC20Permit,
  tokenName: string,
  sourceAddr: string,
  spenderAddr: string,
  nonce: number,
  // '1' for every ERC20Permit.  Except USDC which is '2' ¯\_(ツ)_/¯
  version: string
): Promise<PermitDataStruct | undefined> {
  const typedSigner = signer as unknown as TypedDataSigner;
  // don't use metdata, must match exactly

  // The following line is commented out due a bug in our token's PERMIT_HASH's.  Our tokens are
  // appending a datestring to the name after the PERMIT_HASH is created, which breaks permit calls.
  // After we fix this we can uncomment this line instead of passing in the name as an argument to
  // this function.
  // const name = await token.name();

  const chainId = await signer.getChainId();

  const domain: TypedDataDomain = {
    name: tokenName,
    version: version,
    chainId: chainId,
    verifyingContract: token.address,
  };

  const types: Record<string, TypedDataField[]> = {
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

  if (nonce === undefined || chainId === undefined) {
    return;
  }

  const data = {
    owner: sourceAddr,
    spender: spenderAddr,
    value: ethers.constants.MaxUint256,
    nonce: nonce,
    deadline: ethers.constants.MaxUint256,
  };

  // _signeTypedData is an experimental feature and is not on the type signature!
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sigString: string = await typedSigner._signTypedData(
    domain,
    types,
    data
  );

  const r = `0x${sigString.slice(2, 66)}`;
  const s = `0x${sigString.slice(66, 130)}`;
  const v = `0x${sigString.slice(130, 132)}`;

  return {
    tokenContract: token.address,
    who: spenderAddr,
    amount: ethers.constants.MaxUint256,
    expiration: ethers.constants.MaxUint256,
    r,
    s,
    v,
  };
}
