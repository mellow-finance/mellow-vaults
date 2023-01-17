import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {
    ALL_NETWORKS,
    MAIN_NETWORKS,
    TRANSACTION_GAS_LIMITS,
} from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const { deployer, admin, uniswapV3Factory, usdc, wsteth, weth, wbtc } =
        await getNamedAccounts();
    const factory = await hre.ethers.getContractAt(
        "IUniswapV3Factory",
        uniswapV3Factory
    );
    const pools = [];
    for (const tokens of [
        [usdc, weth],
        [wbtc, weth],
        [usdc, wbtc],
    ]) {
        pools.push(await factory.getPool(tokens[0], tokens[1], 3000));
    }

    for (const tokens of [[wsteth, weth]]) {
        pools.push(await factory.getPool(tokens[0], tokens[1], 500));
    }

    await deploy("UniV3Oracle", {
        from: deployer,
        args: [uniswapV3Factory, pools, admin],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
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
