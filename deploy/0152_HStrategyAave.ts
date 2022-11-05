import { buildHStrategies } from "./0150_HStrategy";

const func = buildHStrategies("Aave");

export default func;
func.tags = ["HStrategy", "polygon"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "AaveVaultGovernance",
    "ERC20RootVaultGovernance",
];
