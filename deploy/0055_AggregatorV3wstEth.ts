import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {MAIN_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { wsteth, chainlinkSteth } = await getNamedAccounts();
    const { deploy } = deployments;
    const { deployer } =
        await getNamedAccounts();
    await deploy("AggregatorV3wstEth", {
        from: deployer,
        args: [wsteth, chainlinkSteth],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
};
export default func;
func.tags = [
    "AggregatorV3wstEth",
    "core",
    ...MAIN_NETWORKS,
];
func.dependencies = [];
