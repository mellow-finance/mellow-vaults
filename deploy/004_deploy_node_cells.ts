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

  await deploy("NodeVaults", {
    from: deployer,
    args: ["Mellow Node Vaults V1", "MNCV1"],
    log: true,
  });
  const nodeVaults = await ethers.getContract("NodeVaults");

  const aaveVaults = await get("AaveVaults");
  const uniV3Vaults = await get("UniV3Vaults");
  const tokenVaults = await get("TokenVaults");
  console.log("Executing addNftAllowedTokens...");

  const receipt = await nodeVaults.addNftAllowedTokens([
    aaveVaults.address,
    uniV3Vaults.address,
    tokenVaults.address,
  ]);
  console.log(`Done with tx: ${receipt.transactionHash}`);
};
export default func;
func.tags = ["NodeVaults"];
