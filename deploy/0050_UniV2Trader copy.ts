import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const { deployer, uniswapV2Router02 } = await getNamedAccounts();
    await deploy("UniV2Trader", {
        from: deployer,
        args: [uniswapV2Router02],
        log: true,
        autoMine: true,
    });
    const tradersCount = (await read("ChiefTrader", "tradersCount")).toNumber();
    if (tradersCount === 1) {
        const uniV2Trader = await get("UniV2Trader");
        await execute(
            "ChiefTrader",
            { from: deployer, log: true, autoMine: true },
            "addTrader",
            uniV2Trader.address
        );
    }
};
export default func;
func.tags = ["UniV2Trader", "Vaults", "Traders"];
