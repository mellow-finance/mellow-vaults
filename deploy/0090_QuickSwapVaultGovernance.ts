import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { TRANSACTION_GAS_LIMITS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    
    const { deployer, algebraPositionManager } = await getNamedAccounts();
    
    if (!algebraPositionManager) {
        return;
    }

    const swapRouter = '0xf5b509bB0909a69B1c207E495f687a596C168E12';
    const farmingCenter = '0x7F281A8cdF66eF5e9db8434Ec6D97acc1bc01E78';
    const dQuickToken = '0x958d208Cdf087843e9AD98d23823d32E17d723A1';
    const quickToken = '0xB5C064F955D8e7F38fE0460C556a72987494eE17';

    const { address: helper } = await deploy("QuickSwapHelper", {
        from: deployer,
        args: [algebraPositionManager],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    const { address: singleton } = await deploy("QuickSwapVault", {
        from: deployer,
        args: [algebraPositionManager, helper, swapRouter, farmingCenter, dQuickToken, quickToken],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    await deploy("QuickSwapVaultGovernance", {
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
func.tags = [
    "QuickSwapVaultGovernance",
    "polygon",
];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
