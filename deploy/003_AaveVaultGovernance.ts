import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { sendTx } from "./000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log } = deployments;
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
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
        const tx = await governance.populateTransaction.initialize(
            factory.address
        );
        await sendTx(hre, tx);
    }
};
export default func;
func.tags = ["AaveVaultGovernance", "Vaults"];
