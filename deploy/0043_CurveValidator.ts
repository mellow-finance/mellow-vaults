import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { MAIN_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const { deployer } = await getNamedAccounts();
    await deploy("CurveValidator", {
        from: deployer,
        args: [protocolGovernance.address],
        log: true,
        autoMine: true,
    });
};
export default func;
func.tags = ["CurveValidator", "core", ...MAIN_NETWORKS];
func.dependencies = ["ProtocolGovernance"];
