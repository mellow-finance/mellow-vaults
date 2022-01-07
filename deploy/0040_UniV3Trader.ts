import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { MAIN_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const { deployer, uniswapV3Router } = await getNamedAccounts();
    const uniV3Trader = await deploy("UniV3Trader", {
        from: deployer,
        args: [uniswapV3Router],
        log: true,
        autoMine: true,
    });
    const traders = (await read("ChiefTrader", "traders")).map((x) =>
        x.toLowerCase()
    );
    if (!traders.include(uniV3Trader.address.toLowerCase())) {
        await execute(
            "ChiefTrader",
            { from: deployer, log: true, autoMine: true },
            "addTrader",
            uniV3Trader.address
        );
    }
};
export default func;
func.tags = [
    "UniV3Trader",
    "core",
    "Traders",
    ...MAIN_NETWORKS,
    "arbitrum",
    "optimism",
    "polygon",
];
func.dependencies = ["ChiefTrader"];
