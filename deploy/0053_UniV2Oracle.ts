import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {
    ALL_NETWORKS,
    MAIN_NETWORKS,
    TRANSACTION_GAS_LIMITS,
} from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const { deployer, uniswapV2Factory } = await getNamedAccounts();
    await deploy("UniV2Oracle", {
        from: deployer,
        args: [uniswapV2Factory],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};
export default func;
func.tags = ["UniV2Oracle", "core", "mainnet"];
