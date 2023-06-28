import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { MAIN_NETWORKS, TRANSACTION_GAS_LIMITS } from "./0000_utils";
import { BigNumber } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, pancakePositionManager } = await getNamedAccounts();

    const { address: mellowOracle } = await get("MellowOracle");
    const { address: singleton } = await deploy("PancakeSwapVault", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
    
    await deploy("PancakeSwapVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
                singleton: singleton,
            },
            {
                positionManager: pancakePositionManager,
                oracle: mellowOracle,
            },
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
};
export default func;
func.tags = [
    "PancakeSwapVaultGovernance",
    "core",
    ...MAIN_NETWORKS,
];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
