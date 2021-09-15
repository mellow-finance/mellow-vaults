import { task, types } from "hardhat/config";

task("setup-basic-strategy", "Mints nfts for basic strategy")
  .addParam("token0", "The name of the token0", undefined, types.string)
  .addParam("token1", "The name of the token1", undefined, types.string)
  .addParam("lowerTick", "Initial lower tick", undefined, types.string)
  .addParam("upperTick", "Initial upper tick", undefined, types.string)
  .setAction(async ({ token0, token1, lowerTick, upperTick }, hre) => {
    const { utils } = hre.ethers;
    const toBytes32 = (x: number) =>
      utils.hexZeroPad(utils.hexlify(x), 32).substr(2);
    const int24ToBytes32 = (x: number) =>
      utils.hexZeroPad(utils.hexlify(x >= 0 ? x : 2 ** 24 + x), 32).substr(2);
    const { deployer, usdc, weth } = await hre.getNamedAccounts();
    const tokens = [usdc, weth].sort();
    const params = `0x${toBytes32(3000)}${int24ToBytes32(
      parseInt(lowerTick)
    )}${int24ToBytes32(parseInt(upperTick))}${toBytes32(100)}${toBytes32(
      100
    )}${toBytes32(0)}${toBytes32(0)}${
      Math.floor(new Date().getTime() / 1000) + 600
    }`;
    console.log(`Calling UniV3Cells#createCell with args ${[tokens, params]}`);

    const receipt = await hre.deployments.execute(
      "UniV3Cells",
      { from: deployer },
      "createCell",
      tokens,
      params
    );
    console.log(receipt);
  });
