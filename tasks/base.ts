import { PopulatedTransaction } from "@ethersproject/contracts";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { utils, BigNumber } from "ethers";

export async function sendTx(
  hre: HardhatRuntimeEnvironment,
  tx: PopulatedTransaction
) {
  console.log("Sending transaction to the pool...");

  const [operator] = await hre.ethers.getSigners();
  const txResp = await operator.sendTransaction(tx);
  console.log(
    `Sent transaction with hash \`${txResp.hash}\`. Waiting confirmation`
  );
  await txResp.wait();
  console.log("Transaction confirmed");
}
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
