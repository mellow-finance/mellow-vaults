import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { sendTx } from "./000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, uniswapV3PositionManager } = await getNamedAccounts();
    await deploy("ERC20VaultGovernance", {
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
    const governance = await hre.ethers.getContract("ERC20VaultGovernance");
    await deploy("ERC20VaultFactory", {
        from: deployer,
        args: [governance.address],
        log: true,
        autoMine: true,
    });
    const initialized = await governance.initialized();
    if (!initialized) {
        log("Initializing factory...");

        const factory = await get("ERC20VaultFactory");
        await sendTx(
            hre,
            await governance.populateTransaction.initialize(factory.address)
        );
    }
};
export default func;
func.tags = ["ERC20VaultGovernance", "Vaults"];
