import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import { TRANSACTION_GAS_LIMITS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer, uniswapV3PositionManager, usdc } =
        await getNamedAccounts();

    const vaultRegistry = await hre.ethers.getContract("VaultRegistry");
    const uniV3Helper = await hre.ethers.getContract("UniV3Helper");

    await deploy("DataCollector", {
        from: deployer,
        args: [
            usdc,
            uniswapV3PositionManager,
            vaultRegistry.address,
            uniV3Helper.address,
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};
export default func;
func.tags = ["DataCollector", "hardhat", "localhost", "mainnet"];
