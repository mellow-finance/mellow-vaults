import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { ALL_NETWORKS } from "./000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, aaveLendingPool } = await getNamedAccounts();
    await deploy("GatewayVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
            },
        ],
        log: true,
        autoMine: true,
    });
    const governance = await get("GatewayVaultGovernance");
    await deploy("GatewayVaultFactory", {
        from: deployer,
        args: [governance.address],
        log: true,
        autoMine: true,
    });
    const initialized = await read("GatewayVaultGovernance", "initialized");
    if (!initialized) {
        log("Initializing factory...");

        const factory = await get("GatewayVaultFactory");
        await execute(
            "GatewayVaultGovernance",
            { from: deployer, log: true, autoMine: true },
            "initialize",
            factory.address
        );
    }
    const { address: gatewayVaultGovernanceAddress } = await get(
        "GatewayVaultFactory"
    );
    const approvedGw = await read(
        "VaultRegistry",
        "isApprovedForAll",
        deployer,
        gatewayVaultGovernanceAddress
    );
    if (!approvedGw) {
        log("Approving gateway vault governance");
        await execute(
            "VaultRegistry",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "setApprovalForAll",
            gatewayVaultGovernanceAddress,
            true
        );
    }
};
export default func;
func.tags = ["GatewayVaultGovernance", "core", ...ALL_NETWORKS];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
