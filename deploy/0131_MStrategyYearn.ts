
import { buildMStrategies } from "./0130_MStrategy";

const func = buildMStrategies("Yearn");

export default func;
func.tags = ["MStrategy", "hardhat", "localhost", "mainnet", "arbitrum"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "YearnVaultGovernance",
    "ERC20RootVaultGovernance",
];
