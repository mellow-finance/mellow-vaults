import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

task("setup-basic-strategy", "Mints nfts for basic strategy")
  .addParam("token0", "The name of the token0", undefined, types.string)
  .addParam("token1", "The name of the token1", undefined, types.string)
  .addParam("fee", "The name of the token1", 3000, types.int)
  .addParam("lowerTick", "Initial lower tick", undefined, types.string)
  .addParam("upperTick", "Initial upper tick", undefined, types.string)
  .addParam(
    "token0Amount",
    "Initial token0 amount for UniV3",
    undefined,
    types.int
  )
  .addParam(
    "token1Amount",
    "Initial token1 amount for UniV3",
    undefined,
    types.int
  )
  .addParam(
    "deadline",
    "The time in secs after which transaction is invalid if not executed",
    300,
    types.int
  )
  .setAction(
    async (
      {
        token0,
        token1,
        fee,
        lowerTick,
        upperTick,
        token0Amount,
        token1Amount,
        deadline,
      },
      hre
    ) => {
      const { utils } = hre.ethers;
      const toBytes32 = (x: number) =>
        utils.hexZeroPad(utils.hexlify(x), 32).substr(2);
      const int24ToBytes32 = (x: number) =>
        utils.hexZeroPad(utils.hexlify(x >= 0 ? x : 2 ** 24 + x), 32).substr(2);

      const feeBytes = int24ToBytes32(parseInt(fee));
      const lowerTickBytes = int24ToBytes32(parseInt(lowerTick));
      const upperTickBytes = int24ToBytes32(parseInt(upperTick));
      const token0AmountBytes = toBytes32(token0Amount);
      const token1AmountBytes = toBytes32(token1Amount);
      const zeroBytes = toBytes32(0);
      const deadlineBytes = toBytes32(
        Math.floor(new Date().getTime() / 1000) + deadline
      );
      const na = await hre.getNamedAccounts();
      const token0Address = na[token0];
      const token1Address = na[token1];
      const tokens = [token0Address, token1Address].sort();
      const params = `0x${feeBytes}${lowerTickBytes}${upperTickBytes}${token0AmountBytes}${token1AmountBytes}${zeroBytes}${zeroBytes}${deadlineBytes}`;
      const uniV3Cells = await hre.ethers.getContract("UniV3Cells");
      await approve(hre, token0, uniV3Cells.address, token0Amount);
      await approve(hre, token1, uniV3Cells.address, token1Amount);
      console.log(
        `Calling UniV3Cells#createCell with args ${[tokens, params]}`
      );
      const tx = await uniV3Cells.createCell(tokens, params);
      const receipt = tx.wait();
      console.log(receipt.transactionHash);
    }
  );

const approve = async (
  hre: HardhatRuntimeEnvironment,
  tokenName: string,
  to: string,
  value: number
) => {
  const token = await hre.getExternalContract(tokenName as any);
  console.log(`Approving ${tokenName} amount ${value} from deployer to ${to}`);
  const tx = await token.approve(to, value);
  const receipt = await tx.wait();
  console.log(receipt.transactionHash);
};
