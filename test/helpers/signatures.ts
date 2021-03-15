import {
  keccak256,
  defaultAbiCoder,
  toUtf8Bytes,
  solidityPack,
} from "ethers/lib/utils";
import { BigNumberish } from "ethers";

const PERMIT_TYPEHASH = keccak256(
  toUtf8Bytes(
    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
  )
);

export function getDigest(
  tokenName: string,
  domainSeparator: string,
  tokenAddress: string,
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
