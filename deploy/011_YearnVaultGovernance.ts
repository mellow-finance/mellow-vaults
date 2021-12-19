import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { MAIN_NETWORKS } from "./000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, yearnVaultRegistry } = await getNamedAccounts();
    await deploy("YearnVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
            },
            { yearnVaultRegistry: yearnVaultRegistry },
        ],
        log: true,
        autoMine: true,
    });
    const governance = await get("YearnVaultGovernance");
    await deploy("YearnVaultFactory", {
        from: deployer,
        args: [governance.address],
        log: true,
        autoMine: true,
    });
    const initialized = await read("YearnVaultGovernance", "initialized");
    if (!initialized) {
        log("Initializing factory...");

        const factory = await get("YearnVaultFactory");
        await execute(
            "YearnVaultGovernance",
            { from: deployer, log: true, autoMine: true },
            "initialize",
            factory.address
        );
    }
};
export default func;
func.tags = ["YearnVaultGovernance", "core", ...MAIN_NETWORKS, "fantom"];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
