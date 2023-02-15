import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { ALL_NETWORKS, TRANSACTION_GAS_LIMITS } from "./0000_utils";
import { ethers } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { uniswapV3PositionManager, deployer, usdc } = await getNamedAccounts();

    const chainlinkOracle = '0x624a5219216c5A101247B39a04260Ed3A2A05B71';  
    const dataUni = await deploy("UniV3Helper", {
        from: deployer,
        args: [
            uniswapV3PositionManager
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    await deploy("ExporterDataCollector", {
        from: deployer,
        args: [
            dataUni.address,
            ethers.constants.AddressZero,
            chainlinkOracle,
            usdc
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};
export default func;
func.tags = ["ExporterDataCollector", "core", ...ALL_NETWORKS];
