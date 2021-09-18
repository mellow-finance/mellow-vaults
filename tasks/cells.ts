import { BigNumber, Contract } from "ethers";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { map, pipe, prop, sortBy, zip } from "ramda";
import { getContract, sendTx } from "./base";
import { getTokenContract } from "./erc20";

task("deposit", "Deposits tokens into cell")
  .addParam("name", "Name of the cells contracts", undefined, types.string)
  .addParam("nft", "Nft of the cell", undefined, types.string)
  .addParam("tokens", "Token names or addresses for deposit", [], types.json)
  .addParam("tokenAmounts", "Token amounts to deposit", [], types.json)
  .setAction(async ({ name, nft, tokens, tokenAmounts }, hre) => {
    await deposit(hre, name, nft, tokens, tokenAmounts.map(BigNumber.from));
  });

task("withdraw", "Withdraw tokens from cell")
  .addParam("name", "Name of the cells contracts", undefined, types.string)
  .addParam("nft", "Nft of the cell", undefined, types.string)
  .addParam("to", "Address to withdraw to", undefined, types.string)
  .addParam("tokens", "Token names or addresses for deposit", [], types.json)
  .addParam("tokenAmounts", "Token amounts to deposit", [], types.json)
  .setAction(async ({ name, nft, to, tokens, tokenAmounts }, hre) => {
    await withdraw(
      hre,
      name,
      nft,
      to,
      tokens,
      tokenAmounts.map(BigNumber.from)
    );
  });

export const deposit = async (
  hre: HardhatRuntimeEnvironment,
  cellsNameOrAddressOrContract: Contract | string,
  nft: BigNumber,
  tokenNameOrAddressOrContracts: string[],
  tokenAmounts: BigNumber[]
) => {
  const { addresses, amounts } = await extractSortedTokenAddressesAndAmounts(
    hre,
    tokenNameOrAddressOrContracts,
    tokenAmounts
  );
  const contract = await getContract(hre, cellsNameOrAddressOrContract);
  await sendTx(
    hre,
    await contract.populateTransaction.deposit(nft, addresses, amounts)
  );
};

export const withdraw = async (
  hre: HardhatRuntimeEnvironment,
  cellsNameOrAddressOrContract: Contract | string,
  nft: BigNumber,
  to: string,
  tokenNameOrAddressOrContracts: string[],
  tokenAmounts: BigNumber[]
) => {
  const { addresses, amounts } = await extractSortedTokenAddressesAndAmounts(
    hre,
    tokenNameOrAddressOrContracts,
    tokenAmounts
  );
  const contract = await getContract(hre, cellsNameOrAddressOrContract);
  await sendTx(
    hre,
    await contract.populateTransaction.withdraw(nft, to, addresses, amounts)
  );
};

const extractSortedTokenAddressesAndAmounts = async (
  hre: HardhatRuntimeEnvironment,
  tokenNameOrAddressOrContracts: string[],
  tokenAmounts: BigNumber[]
): Promise<{ addresses: string[]; amounts: BigNumber[] }> => {
  const tokenContracts = await Promise.all(
    map((name) => getTokenContract(hre, name), tokenNameOrAddressOrContracts)
  );
  const tokenData = pipe(
    map(prop("address")),
    zip(tokenAmounts),
    map(([address, amount]) => ({ address, amount })),
    sortBy(prop("address"))
  )(tokenContracts);
  const sortedAddresses = map(prop("address"), tokenData);
  const sortedAmounts = map(prop("amount"), tokenData);
  // @ts-ignore
  return { addresses: sortedAddresses, amounts: sortedAmounts };
};
