import { BigNumber } from "@ethersproject/bignumber";
import { task, types } from "hardhat/config";
import { Contract } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { createUniV3Cell } from "./uniV3Cells";
import { createCell } from "./cells";
import { approve, safeTransferFrom } from "./erc721";
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
  const aaveNft0 = await createCell(hre, "AaveCells", [token0]);
  const aaveNft1 = await createCell(hre, "AaveCells", [token1]);
  const tokenNft = await createCell(hre, "TokenCells", [token0, token1]);
  const nodeNft = await createCell(hre, "NodeCells", [token0, token1]);
  await moveNftToNodeCells(hre, "UniV3Cells", uniNft, strategist, nodeNft);
  await moveNftToNodeCells(hre, "AaveCells", aaveNft0, strategist, nodeNft);
  await moveNftToNodeCells(hre, "AaveCells", aaveNft1, strategist, nodeNft);
  await moveNftToNodeCells(hre, "TokenCells", tokenNft, strategist, nodeNft);
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
  await approve(hre, tokenNameOrAddressOrContract, nft, to);
  await safeTransferFrom(
    hre,
    tokenNameOrAddressOrContract,
    nft,
    deployer,
    nodeCellsAddress,
    `0x${uintToBytes32(toCell)}`
  );
};
