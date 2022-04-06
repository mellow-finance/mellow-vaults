import hre, { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {ALL_NETWORKS, combineVaults, MAIN_NETWORKS, setupVault} from "./0000_utils";
import {lstat} from "fs";
import {BigNumber} from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read } = deployments;
    const { deployer, uniswapV3PositionManager, cowswap, weth, wsteth, mStrategyTreasury } = await getNamedAccounts();
    const tokens = [weth, wsteth].map((t) => t.toLowerCase()).sort();
    const startNft = (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let uniV3LowerVaultNft = startNft;
    let uniV3UpperVaultNft = startNft + 1;
    let erc20VaultNft = startNft + 2;

    await setupVault(
        hre,
        uniV3LowerVaultNft,
        "UniV3VaultGovernance",
        {
            createVaultArgs: [tokens, deployer, 500,],
        }
    );
    await setupVault(
        hre,
        uniV3UpperVaultNft,
        "UniV3VaultGovernance",
        {
            createVaultArgs: [tokens, deployer, 500,],
        }
    );
    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );
    const uniV3LowerVault = await read(
        "VaultRegistry",
        "vaultForNft",
        uniV3LowerVaultNft
    );
    const uniV3UpperVault = await read(
        "VaultRegistry",
        "vaultForNft",
        uniV3UpperVaultNft
    );

    let strategyDeployParams = await deploy("LStrategy", {
        from: deployer,
        contract: "LStrategy",
        args: [
            uniswapV3PositionManager,
            cowswap,
            erc20Vault,
            uniV3LowerVault,
            uniV3UpperVault,
            deployer,
        ],
        log: true,
        autoMine: true,
    });

    await combineVaults(
        hre,
        erc20VaultNft + 1,
        [erc20VaultNft, uniV3LowerVaultNft, uniV3UpperVaultNft],
        strategyDeployParams.address,
        mStrategyTreasury
    );

    const lStrategy = await ethers.getContract("LStrategy");
    const mellowOracle = await get("MellowOracle");

    await lStrategy.updateTradingParams({
        maxSlippageD: BigNumber.from(10).pow(7),
        oracleSafety: 5,
        minRebalanceWaitTime: 86400,
        orderDeadline: 86400 * 30,
        oracle: mellowOracle.address,
    });

    await lStrategy.updateRatioParams({
        erc20UniV3CapitalRatioD: BigNumber.from(10).pow(7).mul(5), // 0.05 * DENOMINATOR
        erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5), // 0.5 * DENOMINATOR
        minErc20UniV3CapitalRatioDeviationD:
            BigNumber.from(10).pow(8),
        minErc20TokenRatioDeviationD: BigNumber.from(10)
            .pow(8)
            .div(2),
        minUniV3LiquidityRatioDeviationD: BigNumber.from(10)
            .pow(8)
            .div(2),
    });

    await lStrategy.updateOtherParams({
        intervalWidthInTicks: 100,
        minToken0ForOpening: BigNumber.from(10).pow(6),
        minToken1ForOpening: BigNumber.from(10).pow(6),
    });
};

export default func;
func.tags = ["LStrategy", ...MAIN_NETWORKS];
func.dependencies = [
    "ProtocolGovernance",
    "VaultRegistry",
    "MellowOracle",
    "UniV3VaultGovernance",
    "ERC20VaultGovernance",
];