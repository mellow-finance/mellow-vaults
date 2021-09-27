import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("TokenVaults", {
    from: deployer,
    args: ["Mellow Token Vaults V1", "MTCV1"],
    log: true,
  });
};
export default func;
func.tags = ["TokenVaults"];
