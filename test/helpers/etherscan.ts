import axios from "axios";
import { BytesLike } from "ethers";

const API_KEY = "Z73GWKPFXX87ENVY9KK9DK7NJS4ZYA7JM2";

const sourceCodeApiRequest = (address: string) =>
  `https://api.etherscan.io/api?module=contract&action=getsourcecode&address=${address}&apikey=${API_KEY}`;

export async function getContractFunctionSignatureByLabel(
  address: string,
  label: string
): Promise<string> {
  return "ss";
}
