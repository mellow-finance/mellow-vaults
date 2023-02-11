import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {
    TRANSACTION_GAS_LIMITS,
} from "./0000_utils";

const deployHelper = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    await deploy("PulseStrategyHelper", {
        from: deployer,
        contract: "PulseStrategyHelper",
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { bob } = await getNamedAccounts();
    if (!bob) return;
    await deployHelper(hre);
};

export default func;

func.tags = ["SinglePositionStrategy", "polygon"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "UniV3VaultGovernance",
    "ERC20RootVaultGovernance",
];
