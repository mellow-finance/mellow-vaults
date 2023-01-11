import { buildHStrategies } from "./0150_HStrategy";

const func = buildHStrategies("AaveV3");

export default func;
func.tags = ["arbitrum"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "AaveV3VaultGovernance",
    "ERC20RootVaultGovernance",
];
