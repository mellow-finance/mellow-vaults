import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { encodeToBytes } from "../test/library/Helpers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, execute } = deployments;
    const chiefTrader = await get("ChiefTrader");
    const { deployer, uniswapV3Router, admin } = await getNamedAccounts();
    const options = encodeToBytes(["tuple(address swapRouter)"], [{
        swapRouter: uniswapV3Router,
    }]);
    await deploy("UniV3Trader", {
        from: deployer,
        args: [chiefTrader.address, options],
        log: true,
        autoMine: true,
    });
    const uniV3Trader = await get("UniV3Trader");
    await execute(
        "ChiefTrader",
        { from: deployer, log: true, autoMine: true },
        "addTrader",
        uniV3Trader.address
    );
};
export default func;
func.tags = ["UniV3Trader", "Vaults", "Traders"];
