import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { hrtime } from "process";

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
  ethers,
}: HardhatRuntimeEnvironment) {
  const { deploy, execute, get } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("NodeCells", {
    from: deployer,
    args: ["Mellow Node Cells V1", "MNCV1"],
    log: true,
  });
  const nodeCells = await ethers.getContract("NodeCells");

  const aaveCells = await get("AaveCells");
  const uniV3Cells = await get("UniV3Cells");
  const tokenCells = await get("TokenCells");
  console.log("Executing addNftAllowedTokens...");

  const receipt = await nodeCells.addNftAllowedTokens([
    aaveCells.address,
    uniV3Cells.address,
    tokenCells.address,
  ]);
  console.log(`Done with tx: ${receipt.transactionHash}`);
};
export default func;
func.tags = ["NodeCells"];
