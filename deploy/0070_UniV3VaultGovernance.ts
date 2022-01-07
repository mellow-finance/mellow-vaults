import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { MAIN_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, uniswapV3PositionManager } = await getNamedAccounts();
    const { address: mellowOracle } = await get("MellowOracle");
    const { address: singleton } = await deploy("UniV3Vault", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
    });
    await deploy("UniV3VaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
                singleton,
            },
            {
                positionManager: uniswapV3PositionManager,
                oracle: mellowOracle,
            },
        ],
        log: true,
        autoMine: true,
    });
};
export default func;
func.tags = [
    "UniV3VaultGovernance",
    "core",
    ...MAIN_NETWORKS,
    "arbitrum",
    "optimism",
    "polygon",
];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
