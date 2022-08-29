import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { BigNumber } from "ethers";
import {ALL_NETWORKS, MAIN_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, squeethController, uniswapV3Router } = await getNamedAccounts();
    const { address: singleton } = await deploy("SqueethVault", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
    await deploy("SqueethVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
                singleton,
            },
            {
                controller: squeethController,
                router: uniswapV3Router,
            },
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
};
export default func;
func.tags = [
    "SqueethVaultGovernance",
    "core",
    ...MAIN_NETWORKS,
    "avalanche",
    "polygon",
];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
