import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { ALL_NETWORKS, TRANSACTION_GAS_LIMITS } from "./0000_utils";
import { BigNumber } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const { address: protocolGovernance } = await get("ProtocolGovernance");
    const { address: vaultRegistry } = await get("VaultRegistry");
    const { deployer, pancakePositionManager } = await getNamedAccounts();
    const { address: singleton } = await deploy("PancakeSwapVault", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
        gasLimit: BigNumber.from(10).pow(6).mul(6)
    });

    const { address: mellowOracle } = await get("MellowOracle");
    await deploy("PancakeSwapVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance,
                registry: vaultRegistry,
                singleton,
            },
            {
                positionManager: pancakePositionManager,
                oracle: mellowOracle,
            },
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};
export default func;
func.tags = [
    "PancakeSwapVaultGovernance",
    "core",
    ...ALL_NETWORKS,
];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
