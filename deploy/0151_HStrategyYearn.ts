import { buildHStrategies } from "./0150_HStrategy";

const func = buildHStrategies("Yearn");

export default func;
func.tags = ["HStrategy", "hardhat", "localhost", "mainnet", "arbitrum"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "YearnVaultGovernance",
    "ERC20RootVaultGovernance",
];
