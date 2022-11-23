import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { BigNumber, ethers } from "ethers";
import {ALL_NETWORKS, MAIN_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const { deployer, admin, uniswapV3Factory, usdc, weth, squeethWethBorrowPool, opynWeth, opynUsdc, squeethController } =
        await getNamedAccounts();
    console.log(uniswapV3Factory);
    const factory = await hre.ethers.getContractAt(
        "IUniswapV3Factory",
        uniswapV3Factory
    );
    const pools: string[] = [];

    let controller = await hre.ethers.getContractAt("IController", squeethController);
    pools.push(await controller.wPowerPerpPool());
    pools.push(squeethWethBorrowPool);
    await deploy("UniV3Oracle", {
        from: deployer,
        args: [uniswapV3Factory, pools, admin],
        log: true,
        autoMine: true,
        gasLimit: BigNumber.from(10).pow(6).mul(10),
        ...TRANSACTION_GAS_LIMITS
    });
};
export default func;
func.tags = [
    "UniV3Oracle",
    "core",
    ...MAIN_NETWORKS,
    "polygon",
    "arbitrum",
    "optimism",
];
