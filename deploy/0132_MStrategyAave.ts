import { buildMStrategy } from "./0130_MStrategy";

const func = buildMStrategy("Aave");

export default func;
func.tags = ["MStrategy", "polygon"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "AaveVaultGovernance",
    "ERC20RootVaultGovernance",
];
