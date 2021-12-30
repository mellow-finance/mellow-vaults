import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { ALL_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, aaveLendingPool } = await getNamedAccounts();
    await deploy("ERC20RootVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
            },
            { managementFeeChargeDelay: 86400 },
        ],
        log: true,
        autoMine: true,
    });
    const governance = await get("ERC20RootVaultGovernance");
    await deploy("ERC20RootVaultFactory", {
        from: deployer,
        args: [governance.address],
        log: true,
        autoMine: true,
    });
    const initialized = await read("ERC20RootVaultGovernance", "initialized");
    if (!initialized) {
        log("Initializing factory...");

        const factory = await get("ERC20RootVaultFactory");
        await execute(
            "ERC20RootVaultGovernance",
            { from: deployer, log: true, autoMine: true },
            "initialize",
            factory.address
        );
    }
    const { address: lpIssuerVaultGovernanceAddress } = await get(
        "ERC20RootVaultGovernance"
    );
    const approvedIssuer = await read(
        "VaultRegistry",
        "isApprovedForAll",
        deployer,
        lpIssuerVaultGovernanceAddress
    );
    if (!approvedIssuer) {
        log("Approving lp issuer governance");
        await execute(
            "VaultRegistry",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "setApprovalForAll",
            lpIssuerVaultGovernanceAddress,
            true
        );
    }
};
export default func;
func.tags = ["ERC20RootVaultGovernance", "core", ...ALL_NETWORKS];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
