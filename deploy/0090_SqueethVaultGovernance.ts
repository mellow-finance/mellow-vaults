import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { BigNumber } from "ethers";
import {ALL_NETWORKS, MAIN_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, squeethController, uniswapV3Router, uniswapV3Factory, squeethWethBorrowPool } = await getNamedAccounts();
    
    let controllerWeth = await (await hre.ethers.getContractAt("IController", squeethController)).weth();
    const { address: singleton } = await deploy("SqueethVault", {
        from: deployer,
        args: [uniswapV3Factory, controllerWeth],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
    const { address: mellowOracle } = await get("MellowOracle");
    
    const { address: helper } = await deploy("SqueethHelper", {
        from: deployer,
        args: [squeethController],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });

    await deploy("SqueethVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
                singleton,
            },
            {
                controller: squeethController,
                router: uniswapV3Router,
                slippageD9: BigNumber.from(10).pow(7),
                twapPeriod: BigNumber.from(420),
                wethBorrowPool: squeethWethBorrowPool,
                oracle: mellowOracle,
                squeethHelper: helper,
                maxDepegD9: BigNumber.from(10).pow(7).mul(20)
            },
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
};
export default func;
func.tags = [
    "SqueethVaultGovernance",
    "core",
    ...MAIN_NETWORKS
];
func.dependencies = ["ProtocolGovernance", "VaultRegistry", "MellowOracle", "UniV3Validator"];
