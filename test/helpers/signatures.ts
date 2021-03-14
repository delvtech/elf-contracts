import {
  keccak256,
  defaultAbiCoder,
  toUtf8Bytes,
  solidityPack,
} from "ethers/lib/utils";
import { BigNumberish } from "ethers";
export function getDigest(
  domainSeparator: string,
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
            [
              "0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb",
              owner,
              spender,
              value,
              nonce,
              deadline,
            ]
          )
        ),
      ]
    )
  );
}
