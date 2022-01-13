import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { ALL_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const { deployer, uniswapV2Router02 } = await getNamedAccounts();
    const uniV2Trader = await deploy("UniV2Trader", {
        from: deployer,
        args: [uniswapV2Router02],
        log: true,
        autoMine: true,
    });
    const traders = (await read("ChiefTrader", "traders")).map((x: any) =>
        x.toLowerCase()
    );
    if (!traders.includes(uniV2Trader.address.toLowerCase())) {
        await execute(
            "ChiefTrader",
            { from: deployer, log: true, autoMine: true },
            "addTrader",
            uniV2Trader.address
        );
    }
};
export default func;
func.tags = ["UniV2Trader", "core", "Traders", ...ALL_NETWORKS];
func.dependencies = ["ChiefTrader"];
