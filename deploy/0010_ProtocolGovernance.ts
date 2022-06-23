import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {ALL_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";
import {BigNumber} from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer, approver} = await getNamedAccounts();
    await deploy("ProtocolGovernance", {
        from: deployer,
        args: [deployer],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
};
export default func;
func.tags = ["ProtocolGovernance", "core", ...ALL_NETWORKS];
