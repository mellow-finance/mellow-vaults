import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { MAIN_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const { deployer, uniswapV3Router, uniswapV3Factory } =
        await getNamedAccounts();
    await deploy("UniV3Validator", {
        from: deployer,
        args: [protocolGovernance.address, uniswapV3Router, uniswapV3Factory],
        log: true,
        autoMine: true,
    });
};
export default func;
func.tags = [
    "UniV3Validator",
    "core",
    ...MAIN_NETWORKS,
    "polygon",
    "arbitrum",
    "optimism",
];
func.dependencies = ["ProtocolGovernance"];
