import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { ALL_NETWORKS, MAIN_NETWORKS } from "./0000_utils";

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
    });
};
export default func;
func.tags = [
    "UniV3Oracle",
    "core",
    ...MAIN_NETWORKS,
    "polygon",
    "arbitrum",
    "optimism",
];
