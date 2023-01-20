import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {
    combineVaults,
    setupVault,
    TRANSACTION_GAS_LIMITS,
} from "./0000_utils";
import { BigNumberish, BigNumber } from "ethers";

const deployStrategy = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer, algebraPositionManager } = await getNamedAccounts();

    await deploy("SinglePositionStrategyHelper", {
        from: deployer,
        contract: "SinglePositionStrategyHelper",
        args: [algebraPositionManager],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

};

const buildSinglePositionStrategy = async (
    hre: HardhatRuntimeEnvironment,
    tokens: string[],
    mutableParams: MutableParamsStruct
) => {
    const { deployments, getNamedAccounts } = hre;
    const { log, read, execute, get, deploy } = deployments;
    const { deployer, mStrategyTreasury, uniswapV3Router, uniswapV3Factory, algebraPositionManager } =
        await getNamedAccounts();

    tokens = tokens.map((t: string) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let erc20VaultNft = startNft;
    let quickSwapVaultNft = startNft + 1;
    let erc20RootVaultNft = startNft + 2;

    const { address: singlePositionStrategyHelper } = await hre.ethers.getContract(
        "SinglePositionStrategyHelper"
    );

    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );

    await setupVault(hre, quickSwapVaultNft, "QuickSwapVaultGovernance", {
        createVaultArgs: [erc20Vault, tokens],
        delayedStrategyParams: [{
            key: {
                rewardToken: '0x958d208cdf087843e9ad98d23823d32e17d723a1',
                bonusRewardToken: '0xb0b195aefa3650a6908f15cdac7d92f8a5791b0b',
                pool: '0x1f97c0260c6a18b26a9c2681f0faa93ac2182dbc',
                startTime: 1669833619,
                endTime: 4104559500
            },
            bonusTokenToUnderlying: '0xb0b195aefa3650a6908f15cdac7d92f8a5791b0b',
            rewardTokenToUnderlying: '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619',
            swapSlippageD: BigNumber.from(10).pow(7) // 1%
        }],
    });

    const quickSwapVault = await read(
        "VaultRegistry",
        "vaultForNft",
        quickSwapVaultNft
    );

    const deploymentName = "SinglePositionQuickSwapStrategy_BOB_WETH_500";
    const immutableParams = {
        router: uniswapV3Router,
        erc20Vault: erc20Vault,
        quickSwapVault: quickSwapVault,
        tokens: tokens,
    };

    console.log("ImmutableParams:", immutableParams.toString());
    console.log("MutableParams:", mutableParams.toString());

    await deploy(deploymentName, {
        from: deployer,
        contract: "SinglePositionQuickSwapStrategy",
        args: [uniswapV3Factory, algebraPositionManager, singlePositionStrategyHelper],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    const strategy = await hre.ethers.getContract(deploymentName);
    const { address: proxyAddress } = await deploy("TransparentUpgradeableProxy_SinglePositionQuickSwapStrategy", {
        from: deployer,
        contract: "TransparentUpgradeableProxy",
        args: [
            strategy.address,
            deployer,
            []
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    const erc20RootVaultGovernance = await get("ERC20RootVaultGovernance");
    for (let nft of [erc20VaultNft, quickSwapVaultNft]) {
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

    await combineVaults(
        hre,
        erc20RootVaultNft,
        [erc20VaultNft, quickSwapVaultNft],
        proxyAddress,
        mStrategyTreasury
    );

    // const txs: string[] = [];
    // const adminRole = await baseStrategy.ADMIN_ROLE();
    // const adminDelegateRole = await baseStrategy.ADMIN_DELEGATE_ROLE();
    // const operatorRole = await baseStrategy.OPERATOR();

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

    // const strategyOperator = "0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E";
    // if (strategyOperator.length > 0) {
    //     txs.push(
    //         strategy.interface.encodeFunctionData("grantRole", [
    //             operatorRole,
    //             strategyOperator,
    //         ])
    //     );
    // }

    // renounce roles
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
    //         await execute(
    //             deploymentName,
    //             {
    //                 from: deployer,
    //                 log: true,
    //                 autoMine: true,
    //                 ...TRANSACTION_GAS_LIMITS,
    //             },
    //             "multicall",
    //             txs
    //         );
    //         break;
    //     } catch {
    //         log("trying to do multicall again");
    //         continue;
    //     }
    // }
};

type MutableParamsStruct = {
    feeTierOfPoolOfAuxiliaryAnd0Tokens: number;
    feeTierOfPoolOfAuxiliaryAnd1Tokens: number;
    priceImpactD6: number;
    intervalWidth: number;
    tickNeighborhood: number;
    maxDeviationForVaultPool: number;
    maxDeviationForPoolOfAuxiliaryAnd0Tokens: number;
    maxDeviationForPoolOfAuxiliaryAnd1Tokens: number;
    timespanForAverageTick: number;
    auxiliaryToken: string;
    amount0Desired: BigNumberish;
    amount1Desired: BigNumberish;
    swapSlippageD: BigNumberish;
    minSwapAmounts: BigNumberish[];
};

type ImmutableParamsStruct = {
    router: string;
    erc20Vault: string;
    uniV3Vault: string;
    tokens: string[];
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { weth, bob, usdc } = await getNamedAccounts();

    if (!bob) return;
    await deployStrategy(hre);
    await buildSinglePositionStrategy(hre, [weth, bob], {
        feeTierOfPoolOfAuxiliaryAnd0Tokens: 500, // weth-usdc 0.05%
        feeTierOfPoolOfAuxiliaryAnd1Tokens: 100, // bob-usdc 0.01%
        priceImpactD6: 0,
        intervalWidth: 1600,
        tickNeighborhood: 50,
        maxDeviationForVaultPool: 50,
        maxDeviationForPoolOfAuxiliaryAnd0Tokens: 50, // weth-usdc 0.05%
        maxDeviationForPoolOfAuxiliaryAnd1Tokens: 25, // bob-usdc 0.01%
        timespanForAverageTick: 60,
        auxiliaryToken: usdc,
        amount0Desired: 10 ** 9, // weth
        amount1Desired: 10 ** 9, // bob
        swapSlippageD: 10 ** 7,
        minSwapAmounts: [BigNumber.from(10).pow(13), BigNumber.from(10).pow(15)]
    } as MutableParamsStruct);
};

export default func;

func.tags = ["SinglePositionStrategy", "polygon"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "UniV3VaultGovernance",
    "ERC20RootVaultGovernance",
];
