import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, aaveLendingPool } = await getNamedAccounts();
    await deploy("AaveVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
            },
            { lendingPool: aaveLendingPool },
        ],
        log: true,
        autoMine: true,
    });
    const governance = await hre.ethers.getContract("AaveVaultGovernance");
    await deploy("AaveVaultFactory", {
        from: deployer,
        args: [governance.address],
        log: true,
        autoMine: true,
    });
    const initialized = await governance.initialized();
    if (!initialized) {
        log("Initializing factory...");

        const factory = await get("AaveVaultFactory");
        const receipt = await governance.initialize(factory.address);
        log(`Initialized with txHash ${receipt.hash}`);
    }
};
export default func;
func.tags = ["ProtocolGovernance", "Vaults"];
