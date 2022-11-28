import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {
    combineVaults,
    setupVault,
    TRANSACTION_GAS_LIMITS,
} from "./0000_utils";
import { BigNumber, BigNumberish } from "ethers";
import { F, map } from "ramda";
import { ethers } from "hardhat";

const deployHelpers = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer, uniswapV3PositionManager } = await getNamedAccounts();

    await deploy("UniV3Helper", {
        from: deployer,
        contract: "UniV3Helper",
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    await deploy("MultiPoolHStrategyRebalancer", {
        from: deployer,
        contract: "MultiPoolHStrategyRebalancer",
        args: [uniswapV3PositionManager, deployer],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};

const deployMultiPoolHStrategy = async function (
    hre: HardhatRuntimeEnvironment,
    constructorParams: MultiPoolStrategyConstructorParams,
    deploymentName: string,
    vaults: VaultsAddresses
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const { address: rebalancer } = await hre.ethers.getContract(
        "MultiPoolHStrategyRebalancer"
    );

    await deploy(deploymentName, {
        from: deployer,
        contract: "MultiPoolHStrategy",
        args: [
            constructorParams.token0,
            constructorParams.token1,
            vaults.erc20Vault,
            vaults.moneyVault,
            constructorParams.router,
            rebalancer,
            deployer,
            vaults.uniV3Vaults,
            constructorParams.tickSpacing,
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    const { address } = await deployments.get(deploymentName);
    return await hre.ethers.getContractAt("MultiPoolHStrategy", address);
};

const setupStrategy = async (
    hre: HardhatRuntimeEnvironment,
    deploymentName: string,
    constructorParams: MultiPoolStrategyConstructorParams,
    mutableParams: MultiPoolStrategyMutableParams,
    vaults: VaultsAddresses
) => {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read } = deployments;
    const { deployer, mStrategyAdmin } = await getNamedAccounts();

    const strategy = await deployMultiPoolHStrategy(
        hre,
        constructorParams,
        deploymentName,
        vaults
    );
    const txs: string[] = [];
    for (var uniV3Vault of vaults.uniV3Vaults) {
        let vault = await ethers.getContractAt("UniV3Vault", uniV3Vault);
        const pool = await ethers.getContractAt(
            "IUniswapV3Pool",
            await vault.pool()
        );
        const fee = await pool.fee();
        if (fee.toString() == mutableParams.swapPool) {
            mutableParams.swapPool = pool.address;
            break;
        }
    }
    txs.push(
        strategy.interface.encodeFunctionData("updateMutableParams", [
            mutableParams,
        ])
    );

    log(
        `Mutable Params:`,
        map((x) => x.toString(), mutableParams)
    );

    // const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");
    // const adminDelegateRole = await read(
    //     "ProtocolGovernance",
    //     "ADMIN_DELEGATE_ROLE"
    // );
    // const operatorRole = await read("ProtocolGovernance", "OPERATOR");

    // txs.push(
    //     strategy.interface.encodeFunctionData("grantRole", [
    //         adminDelegateRole,
    //         deployer,
    //     ])
    // );

    // txs.push(
    //     strategy.interface.encodeFunctionData("grantRole", [
    //         adminRole,
    //         mStrategyAdmin,
    //     ])
    // );

    // const hStrategyOperator = "0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E";
    // if (hStrategyOperator.length > 0) {
    //     txs.push(
    //         strategy.interface.encodeFunctionData("grantRole", [
    //             operatorRole,
    //             hStrategyOperator,
    //         ])
    //     );
    // }

    // // renounce roles
    // txs.push(
    //     strategy.interface.encodeFunctionData("renounceRole", [
    //         operatorRole,
    //         deployer,
    //     ])
    // );

    // txs.push(
    //     strategy.interface.encodeFunctionData("renounceRole", [
    //         adminDelegateRole,
    //         deployer,
    //     ])
    // );

    // txs.push(
    //     strategy.interface.encodeFunctionData("renounceRole", [
    //         adminRole,
    //         deployer,
    //     ])
    // );

    // while (true) {
    //     try {
    // await execute(
    //     deploymentName,
    //     {
    //         from: deployer,
    //         log: true,
    //         autoMine: true,
    //         ...TRANSACTION_GAS_LIMITS,
    //     },
    //     "multicall",
    //     txs
    // );
    //         break;
    //     } catch {
    //         console.log("Fucked")
    //         log("trying to do multicall again");
    //         continue;
    //     }
    // }
};

const buildMultiPoolHStrategy = async (
    hre: HardhatRuntimeEnvironment,
    tokens: string[],
    constructorParams: MultiPoolStrategyConstructorParams,
    mutableParams: MultiPoolStrategyMutableParams,
    moneyGovernance: string
) => {
    const { deployments, getNamedAccounts } = hre;
    const { log, read, execute, get } = deployments;
    const { deployer, mStrategyTreasury } = await getNamedAccounts();
    tokens = tokens.map((t: string) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let erc20VaultNft = startNft;
    let moneyVaultNft = startNft + 1;
    let uniV3VaultNft500 = startNft + 2;
    let uniV3VaultNft3000 = startNft + 3;
    let erc20RootVaultNft = startNft + 4;

    const { address: uniV3Helper } = await hre.ethers.getContract(
        "UniV3Helper"
    );

    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    await setupVault(hre, moneyVaultNft, moneyGovernance, {
        createVaultArgs: [tokens, deployer],
    });

    await setupVault(hre, uniV3VaultNft500, "UniV3VaultGovernance", {
        createVaultArgs: [tokens, deployer, 500, uniV3Helper],
    });

    await setupVault(hre, uniV3VaultNft3000, "UniV3VaultGovernance", {
        createVaultArgs: [tokens, deployer, 3000, uniV3Helper],
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );
    const moneyVault = await read(
        "VaultRegistry",
        "vaultForNft",
        moneyVaultNft
    );

    const uniV3Vault500 = await read(
        "VaultRegistry",
        "vaultForNft",
        uniV3VaultNft500
    );

    const uniV3Vault3000 = await read(
        "VaultRegistry",
        "vaultForNft",
        uniV3VaultNft3000
    );

    const deploymentName =
        "MultiPoolHStrategy_" + (moneyGovernance[0] == "A" ? "Aave" : "Yearn");
    const vaults: VaultsAddresses = {
        erc20Vault: erc20Vault,
        moneyVault: moneyVault,
        uniV3Vaults: [uniV3Vault500, uniV3Vault3000],
    };

    await setupStrategy(
        hre,
        deploymentName,
        constructorParams,
        mutableParams,
        vaults
    );

    const erc20RootVaultGovernance = await get("ERC20RootVaultGovernance");
    for (let nft of [
        erc20VaultNft,
        moneyVaultNft,
        uniV3VaultNft500,
        uniV3VaultNft3000,
    ]) {
        log("Approve nft for vault registry: " + nft.toString());
        await execute(
            "VaultRegistry",
            {
                from: deployer,
                log: true,
                autoMine: true,
                ...TRANSACTION_GAS_LIMITS,
            },
            "approve",
            erc20RootVaultGovernance.address,
            nft
        );
    }

    const { address: strategyAddress } = await get(deploymentName);
    const strategy = await ethers.getContractAt(
        "MultiPoolHStrategy",
        strategyAddress
    );
    await combineVaults(
        hre,
        erc20RootVaultNft,
        [erc20VaultNft, moneyVaultNft, uniV3VaultNft500, uniV3VaultNft3000],
        await strategy.rebalancer(),
        mStrategyTreasury
    );
};

type VaultsAddresses = {
    erc20Vault: string;
    moneyVault: string;
    uniV3Vaults: string[];
};

type MultiPoolStrategyConstructorParams = {
    token0: string;
    token1: string;
    router: string;
    tickSpacing: BigNumberish;
};

type MultiPoolStrategyMutableParams = {
    halfOfShortInterval: BigNumberish;
    domainLowerTick: BigNumberish;
    domainUpperTick: BigNumberish;
    maxTickDeviation: BigNumberish;
    averageTickTimespan: BigNumberish;
    amount0ForMint: BigNumberish;
    amount1ForMint: BigNumberish;
    erc20CapitalRatioD: BigNumberish;
    uniV3Weights: BigNumberish[];
    swapPool: string;
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { weth, usdc, wbtc, uniswapV3Router } = await getNamedAccounts();

    await deployHelpers(hre);
    await buildMultiPoolHStrategy(
        hre,
        [usdc, weth],
        {
            token0: usdc,
            token1: weth,
            router: uniswapV3Router,
            tickSpacing: 60,
        } as MultiPoolStrategyConstructorParams,
        {
            halfOfShortInterval: 1800,
            domainLowerTick: 190800,
            domainUpperTick: 219600,
            maxTickDeviation: 100,
            averageTickTimespan: 30,
            amount0ForMint: 10 ** 9,
            amount1ForMint: 10 ** 9,
            erc20CapitalRatioD: BigNumber.from(10).pow(9).div(100), // 1%
            uniV3Weights: [1, 1],
            swapPool: "500",
        } as MultiPoolStrategyMutableParams,
        "AaveVaultGovernance"
    );
};

export default func;

func.tags = [
    "MultiPoolHStrategy",
    "hardhat",
    "localhost",
    "mainnet",
    "polygon",
];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "YearnVaultGovernance",
    "UniV3VaultGovernance",
    "ERC20RootVaultGovernance",
];
