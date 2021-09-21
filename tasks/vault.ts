import { BigNumber } from "@ethersproject/bignumber";
import { task, types } from "hardhat/config";
import { Contract } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { createUniV3Cell } from "./uniV3Cells";
import { createCell, deposit, withdraw } from "./cells";
import { safeTransferFrom, approve as approve721 } from "./erc721";
import { approve } from "./erc20";
import { resolveAddress, uintToBytes32 } from "./base";

task("create-vault-1", "Mints nft for vault-1 strategy")
  .addParam("token0", "The name of the token0", undefined, types.string)
  .addParam("token1", "The name of the token1", undefined, types.string)
  .addParam("fee", "The name of the token1", 3000, types.int)
  .addParam("lowerTick", "Initial lower tick", undefined, types.string)
  .addParam("upperTick", "Initial upper tick", undefined, types.string)
  .addParam("amount0", "Initial token0 amount for UniV3", "100", types.string)
  .addParam("amount1", "Initial token1 amount for UniV3", "100", types.string)
  .addParam(
    "strategist",
    "Address of vault strategist",
    undefined,
    types.string
  )
  .setAction(
    async (
      {
        token0,
        token1,
        fee,
        lowerTick,
        upperTick,
        amount0,
        amount1,
        strategist,
      },
      hre
    ) => {
      await createVault1(
        hre,
        token0,
        token1,
        fee,
        parseInt(lowerTick),
        parseInt(upperTick),
        BigNumber.from(amount0),
        BigNumber.from(amount1),
        strategist
      );
    }
  );

export const createVault1 = async (
  hre: HardhatRuntimeEnvironment,
  token0: string | Contract,
  token1: string | Contract,
  fee: number,
  lowerTick: number,
  upperTick: number,
  amount0: BigNumber,
  amount1: BigNumber,
  strategist: string
) => {
  const aaveAddress = await resolveAddress(hre, "AaveCells");
  const tokenAddress = await resolveAddress(hre, "TokenCells");
  const nodeAddress = await resolveAddress(hre, "NodeCells");

  await approve(hre, token0, aaveAddress, amount0);
  await approve(hre, token1, aaveAddress, amount1);
  await approve(hre, token0, tokenAddress, amount0);
  await approve(hre, token1, tokenAddress, amount1);
  await approve(hre, token0, nodeAddress, amount0);
  await approve(hre, token1, nodeAddress, amount1);
  const uniNft = await createUniV3Cell(
    hre,
    token0,
    token1,
    fee,
    lowerTick,
    upperTick,
    amount0,
    amount1,
    BigNumber.from(0),
    BigNumber.from(0),
    1800
  );
  const aaveNft = await createCell(hre, "AaveCells", [token0, token1]);
  const tokenNft = await createCell(hre, "TokenCells", [token0, token1]);
  const nodeNft = await createCell(hre, "NodeCells", [token0, token1]);
  await deposit(
    hre,
    "AaveCells",
    aaveNft,
    [token0, token1],
    [amount0, amount1]
  );
  await deposit(
    hre,
    "TokenCells",
    tokenNft,
    [token0, token1],
    [amount0, amount1]
  );

  await moveNftToNodeCells(hre, "UniV3Cells", uniNft, strategist, nodeNft);
  await moveNftToNodeCells(hre, "AaveCells", aaveNft, strategist, nodeNft);
  await moveNftToNodeCells(hre, "TokenCells", tokenNft, strategist, nodeNft);
  await deposit(
    hre,
    "NodeCells",
    nodeNft,
    [token0, token1],
    [amount0, amount1]
  );
  // await withdraw(
  //   hre,
  //   "NodeCells",
  //   nodeNft,
  //   (
  //     await hre.getNamedAccounts()
  //   ).deployer,
  //   [token0, token1],
  //   [amount0, amount1]
  // );
};

export const moveNftToNodeCells = async (
  hre: HardhatRuntimeEnvironment,
  tokenNameOrAddressOrContract: string | Contract,
  nft: BigNumber,
  to: string,
  toCell: BigNumber
) => {
  console.log(
    `Moving nft \`${nft.toString()}\` in contract \`${tokenNameOrAddressOrContract}\` to NodeCells`
  );
  const { deployer } = await hre.getNamedAccounts();
  const nodeCellsAddress = await resolveAddress(hre, "NodeCells");
  await approve721(hre, tokenNameOrAddressOrContract, nft, to);
  await safeTransferFrom(
    hre,
    tokenNameOrAddressOrContract,
    nft,
    deployer,
    nodeCellsAddress,
    `0x${uintToBytes32(toCell)}`
  );
};
