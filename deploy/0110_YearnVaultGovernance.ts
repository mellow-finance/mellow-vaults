import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {MAIN_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";
import {BigNumber} from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    // const { deployments, getNamedAccounts } = hre;
    // const { deploy, get, log, execute, read } = deployments;
    // const protocolGovernance = await hre.ethers.getContract(
    //     "ProtocolGovernance"
    // );
    // const vaultRegistry = await get("VaultRegistry");
    // const { deployer, yearnVaultRegistry } = await getNamedAccounts();
    // const { address: singleton } = await deploy("YearnVault", {
    //     from: deployer,
    //     args: [],
    //     log: true,
    //     autoMine: true,
    //     ...TRANSACTION_GAS_LIMITS
    // });
    // await deploy("YearnVaultGovernance", {
    //     from: deployer,
    //     args: [
    //         {
    //             protocolGovernance: protocolGovernance.address,
    //             registry: vaultRegistry.address,
    //             singleton,
    //         },
    //         { yearnVaultRegistry: yearnVaultRegistry },
    //     ],
    //     log: true,
    //     autoMine: true,
    //     ...TRANSACTION_GAS_LIMITS
    // });
};
export default func;
func.tags = ["YearnVaultGovernance", "core", ...MAIN_NETWORKS, "fantom", "arbitrum"];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
