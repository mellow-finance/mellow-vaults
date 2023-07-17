import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { ALL_NETWORKS, TRANSACTION_GAS_LIMITS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { deployer } = await getNamedAccounts();
    const { address: singleton } = await deploy("ERC20Vault", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
    await deploy("ERC20VaultGovernance", {
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
        ...TRANSACTION_GAS_LIMITS,
    });
};
export default func;
func.tags = ["ERC20VaultGovernance", "core", ...ALL_NETWORKS];
func.dependencies = [
    "ProtocolGovernance",
    "VaultRegistry",
    "ChiefTrader",
    "UniV2Trader",
];
