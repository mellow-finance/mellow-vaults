import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {ALL_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    return;
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    console.log("Deployer: ", deployer);
    await deploy("WhiteList", {
        from: deployer,
        args: [deployer],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
};
export default func;
func.tags = ["WhiteList", "core", ...ALL_NETWORKS];
func.dependencies = [];
