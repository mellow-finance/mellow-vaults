import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { MAIN_NETWORKS, TRANSACTION_GAS_LIMITS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, voltzPeriphery } = await getNamedAccounts();
    const { address: singleton } = await deploy("VoltzVault", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    await deploy("VoltzVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
                singleton,
            },
            {
                periphery: voltzPeriphery,
            },
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};


export default func;
func.tags = [
    "VoltzVaultGovernance",
    "core",
    ...MAIN_NETWORKS,
    "arbitrum",
    "optimism",
    "polygon",
];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
