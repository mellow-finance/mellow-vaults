import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { ALL_NETWORKS, MAIN_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const vaultRegistry = await get("VaultRegistry");
    const { deployer } = await getNamedAccounts();
    const { address: singleton } = await deploy("MellowVault", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
    });
    await deploy("MellowVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
                singleton,
            },
        ],
        log: true,
        autoMine: true,
    });
};
export default func;
func.tags = ["MellowVaultGovernance", "core", ...ALL_NETWORKS];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
