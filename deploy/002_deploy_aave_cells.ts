import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;

  const { deployer, aaveLendingPool } = await getNamedAccounts();

  await deploy("AaveVaults", {
    from: deployer,
    args: [aaveLendingPool, "Mellow Aave Vaults V1", "MACV1"],
    log: true,
  });
};
export default func;
func.tags = ["AaveVaults"];
