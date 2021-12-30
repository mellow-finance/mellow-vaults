import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { ALL_NETWORKS, MAIN_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const { deployer, uniswapV2Factory } = await getNamedAccounts();
    await deploy("UniV2Oracle", {
        from: deployer,
        args: [uniswapV2Factory],
        log: true,
        autoMine: true,
    });
};
export default func;
func.tags = ["UniV2Oracle", "core", ...ALL_NETWORKS];
