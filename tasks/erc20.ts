import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Contract, BigNumber } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { sendTx } from "./base";

export const approve = async (
  hre: HardhatRuntimeEnvironment,
  tokenNameOrAddressOrContract: string | Contract,
  to: string,
  value: BigNumber
) => {
  const token = await getTokenContract(hre, tokenNameOrAddressOrContract);
  if ((await token.allowance(to)).gte(value)) {
    console.log(
      `Approving token ${token.address} to ${to} with value ${value.toString()}`
    );
    sendTx(hre, await token.populateTransaction.approve(to, value));
  }
};

const getTokenContractByNameOrAddress = async (
  hre: HardhatRuntimeEnvironment,
  tokenNameOrAddress: string
): Promise<Contract> => {
  try {
    return await hre.getExternalContract(tokenNameOrAddress);
  } catch {
    if (!hre.ethers.utils.isAddress(tokenNameOrAddress)) {
      throw `Token contract ${tokenNameOrAddress} not found`;
    }
    const abi = require("./abi/erc20.abi.json");
    return await hre.ethers.getContractAt(abi, tokenNameOrAddress);
  }
};

export const getTokenContract = async (
  hre: HardhatRuntimeEnvironment,
  tokenNameOrAddressOrContract: string | Contract
): Promise<Contract> => {
  if (tokenNameOrAddressOrContract instanceof Contract) {
    return tokenNameOrAddressOrContract;
  }
  return await getTokenContractByNameOrAddress(
    hre,
    tokenNameOrAddressOrContract
  );
};
