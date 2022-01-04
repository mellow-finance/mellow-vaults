import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { ALL_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    await deploy("ProtocolGovernance", {
        from: deployer,
        args: [deployer],
        log: true,
        autoMine: true,
    });
};
export default func;
func.tags = ["ProtocolGovernance", "core", ...ALL_NETWORKS];
