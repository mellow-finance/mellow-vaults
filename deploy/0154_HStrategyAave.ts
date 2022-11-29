import { buildHStrategies } from "./0153_HStrategyConfigurable";

const func = buildHStrategies("Aave");

export default func;
func.tags = ["HStrategyConfigurable", "polygon"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "AaveVaultGovernance",
    "ERC20RootVaultGovernance",
];
