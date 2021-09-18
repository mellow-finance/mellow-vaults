import { PopulatedTransaction } from "@ethersproject/contracts";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { utils, BigNumber, Contract } from "ethers";
import { TransactionReceipt } from "@ethersproject/abstract-provider";

export async function sendTx(
  hre: HardhatRuntimeEnvironment,
  tx: PopulatedTransaction
): Promise<TransactionReceipt> {
  console.log("Sending transaction to the pool...");

  const [operator] = await hre.ethers.getSigners();
  const txResp = await operator.sendTransaction(tx);
  console.log(
    `Sent transaction with hash \`${txResp.hash}\`. Waiting confirmation`
  );
  const receipt = await txResp.wait();
  console.log("Transaction confirmed");
  return receipt;
}

export const getContract = async (
  hre: HardhatRuntimeEnvironment,
  contractOrNameOrAddress: Contract | string
): Promise<Contract> => {
  if (contractOrNameOrAddress instanceof Contract) {
    return contractOrNameOrAddress;
  }
  const deployments = await hre.deployments.all();
  for (const name in deployments) {
    const deployment = deployments[name];
    if (
      name === contractOrNameOrAddress ||
      deployment.address === contractOrNameOrAddress
    ) {
      return await hre.ethers.getContractAt(name, deployment.address);
    }
  }
  throw `Contract \`${contractOrNameOrAddress}\` is not found`;
};

export const impersonate = async (
  hre: HardhatRuntimeEnvironment,
  accountName: string
) => {
  const address = (await hre.getNamedAccounts())[accountName];
  if (!address)
    throw `Cannot impersonate account ${accountName}. Not found in Named Accounts`;
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  console.log(`Impersonated ${accountName}`);
};

export const uintToBytes32 = (x: BigNumber) =>
  utils.hexZeroPad(utils.hexlify(x), 32).substr(2);
export const int24ToBytes32 = (x: BigNumber) =>
  utils
    .hexZeroPad(
      utils.hexlify(x.toNumber() >= 0 ? x.toNumber() : 2 ** 24 + x.toNumber()),
      32
    )
    .substr(2);
