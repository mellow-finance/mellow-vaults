import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {ALL_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer, squeethShortPositionHelper } = await getNamedAccounts();
    // await deploy("SqueethVault", {
    //     from: deployer,
    //     args: [
    //         squeethShortPositionHelper
    //     ],
    //     log: true,
    //     autoMine: true,
    //     ...TRANSACTION_GAS_LIMITS
    // });
};
export default func;
func.tags = ["SqueethVault", "core", ...ALL_NETWORKS];
func.dependencies = [];
