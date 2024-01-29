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
    const { deployer } = await getNamedAccounts();

    await deploy("QuickPulseStrategyHelper", {
        from: deployer,
        contract: "QuickPulseStrategyHelper",
        args: [],
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
    const {
        deployer,
        mStrategyTreasury,
        aggregationRouterV5,
        uniswapV3PositionManager,
    } = await getNamedAccounts();

    tokens = tokens.map((t: string) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let erc20VaultNft = startNft;
    let quickSwapVaultNft = startNft + 1;
    let erc20RootVaultNft = startNft + 2;

    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );

    await setupVault(hre, quickSwapVaultNft, "QuickSwapVaultGovernance", {
        createVaultArgs: [tokens, deployer, erc20Vault],
        delayedStrategyParams: [
            [
                "0x958d208cdf087843e9ad98d23823d32e17d723a1",
                "0xb0b195aefa3650a6908f15cdac7d92f8a5791b0b",
                "0x1f97c0260c6a18b26a9c2681f0faa93ac2182dbc",
                1669833619,
                4104559500,
            ],
            "0xb0b195aefa3650a6908f15cdac7d92f8a5791b0b",
            "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619",
            10000000,
        ],
    });

    const quickSwapVault = await read(
        "VaultRegistry",
        "vaultForNft",
        quickSwapVaultNft
    );

    const deploymentName = "QuickPulseStrategy";
    const immutableParams = {
        router: aggregationRouterV5,
        erc20Vault: erc20Vault,
        quickSwapVault: quickSwapVault,
        tokens: tokens,
    } as ImmutableParamsStruct;

    console.log("ImmutableParams:", immutableParams);
    console.log("MutableParams:", mutableParams);

    await deploy(deploymentName, {
        from: deployer,
        contract: "PulseStrategy",
        args: [uniswapV3PositionManager],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    const strategy = await hre.ethers.getContract(deploymentName);
    const { address: proxyAddress } = await deploy(
        "QuickPulseStrategyProxyShort",
        {
            from: deployer,
            contract: "TransparentUpgradeableProxy",
            args: [strategy.address, deployer, []],
            log: true,
            autoMine: true,
            ...TRANSACTION_GAS_LIMITS,
        }
    );

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
    priceImpactD6: BigNumberish;
    intervalWidth: BigNumberish;
    tickNeighborhood: BigNumberish;
    maxDeviationForVaultPool: BigNumberish;
    timespanForAverageTick: BigNumberish;
    amount0Desired: BigNumberish;
    amount1Desired: BigNumberish;
    swapSlippageD: BigNumberish;
    swappingAmountsCoefficientD: BigNumberish;
    minSwapAmounts: BigNumberish[];
};

type ImmutableParamsStruct = {
    router: string;
    erc20Vault: string;
    quickSwapVault: string;
    tokens: string[];
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { weth, bob } = await getNamedAccounts();

    if (!bob) return;
    await deployStrategy(hre);
    await buildSinglePositionStrategy(hre, [weth, bob], {
        priceImpactD6: 0,
        intervalWidth: 2400,
        tickNeighborhood: 200,
        maxDeviationForVaultPool: 50,
        timespanForAverageTick: 60,
        amount0Desired: 10 ** 9, // weth
        amount1Desired: 10 ** 9, // bob
        swapSlippageD: 10 ** 7,
        swappingAmountsCoefficientD: 10 ** 7,
        minSwapAmounts: [
            BigNumber.from(10).pow(13),
            BigNumber.from(10).pow(15),
        ],
    } as MutableParamsStruct);
};

export default func;

func.tags = ["QuickPulseStrategy", "polygon"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "QuickSwapVaultGovernance",
    "ERC20RootVaultGovernance",
];
