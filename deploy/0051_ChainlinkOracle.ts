import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { MAIN_NETWORKS, TRANSACTION_GAS_LIMITS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const {
        deployer,
        admin,
        weth,
        wbtc,
        usdc,
        chainlinkEth,
        chainlinkBtc,
        chainlinkUsdc,
    } = await getNamedAccounts();
    await deploy("ChainlinkOracle", {
        from: deployer,
        args: [
            [weth, wbtc, usdc],
            [chainlinkEth, chainlinkBtc, chainlinkUsdc],
            admin,
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};
export default func;
func.tags = ["ChainlinkOracle", "core", ...MAIN_NETWORKS];
