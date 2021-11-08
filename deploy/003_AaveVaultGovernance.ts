import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get } = deployments;
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
    const governance = await get("AaveVaultGovernance");
    await deploy("AaveVaultFactory", {
        from: deployer,
        args: [governance.address],
        log: true,
        autoMine: true,
    });
    const factory = await get("AaveVaultFactory");
    // await factory. initialize()
};
export default func;
func.tags = ["ProtocolGovernance", "Vaults"];
