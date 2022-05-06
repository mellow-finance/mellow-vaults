import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { ALL_NETWORKS, MAIN_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const { deployer, admin, uniswapV3Factory, usdc, weth, wbtc } =
        await getNamedAccounts();
    const factory = await hre.ethers.getContractAt(
        "IUniswapV3Factory",
        uniswapV3Factory
    );
    const pools = [];
    // usdc 0x2791
    // weth 0x7ceb
    // wbtc 0x1bf
    for (const tokens of [
        [usdc, weth],
        [wbtc, weth],
        [usdc, wbtc],
    ]) {
        console.log("TOKENS:", tokens[0], tokens[1]);
        console.log(await factory.getPool(tokens[0].toLowerCase(), tokens[1].toLowerCase(), 3000));
        pools.push(await factory.getPool(tokens[0].toLowerCase(), tokens[1].toLowerCase(), 3000));
    }

    console.log(uniswapV3Factory);
    console.log("pools:", pools);
    console.log(admin);

    await deploy("UniV3Oracle", {
        from: deployer,
        args: [uniswapV3Factory, pools, admin],
        log: true,
        autoMine: true,
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
