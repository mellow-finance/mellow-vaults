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
    const { deployer, uniswapV3PositionManager } = await getNamedAccounts();

    await deploy("UniV3Helper", {
        from: deployer,
        contract: "UniV3Helper",
        args: [uniswapV3PositionManager],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    await deploy("SinglePositionStrategy", {
        from: deployer,
        contract: "SinglePositionStrategy",
        args: [uniswapV3PositionManager],
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
    const { log, read, execute, get } = deployments;
    const { deployer, mStrategyTreasury, uniswapV3Router, mStrategyAdmin } =
        await getNamedAccounts();

    tokens = tokens.map((t: string) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let erc20VaultNft = startNft;
    let uniV3VaultNft500 = startNft + 1;
    let erc20RootVaultNft = startNft + 2;

    const { address: uniV3Helper } = await hre.ethers.getContract(
        "UniV3Helper"
    );

    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    await setupVault(hre, uniV3VaultNft500, "UniV3VaultGovernance", {
        createVaultArgs: [tokens, deployer, 500, uniV3Helper],
        delayedStrategyParams: [2],
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );

    const uniV3Vault500 = await read(
        "VaultRegistry",
        "vaultForNft",
        uniV3VaultNft500
    );

    const deploymentName = "SinglePositionStrategy_BOB_WETH_500";

    const immutableParams = {
        tokens: tokens,
        router: uniswapV3Router,
        uniV3Vault: uniV3Vault500,
        erc20Vault: erc20Vault,
    } as ImmutableParamsStruct;

    const baseStrategy = await hre.ethers.getContract("SinglePositionStrategy");

    const newStrategyAddress = await baseStrategy
        .connect(deployer)
        .callStatic.createStrategy(immutableParams, mutableParams, deployer);

    const erc20RootVaultGovernance = await get("ERC20RootVaultGovernance");
    for (let nft of [erc20VaultNft, uniV3VaultNft500]) {
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
        [erc20VaultNft, uniV3VaultNft500],
        newStrategyAddress,
        mStrategyTreasury
    );

    await execute(
        "SinglePositionStrategy",
        {
            from: deployer,
            log: true,
            autoMine: true,
            ...TRANSACTION_GAS_LIMITS,
        },
        "createStrategy",
        immutableParams,
        mutableParams,
        deployer
    );

    const strategy = await hre.ethers.getContractAt(
        "SinglePositionStrategy",
        newStrategyAddress
    );
    console.log("Strategy address:", newStrategyAddress);
    await deployments.save(deploymentName, {
        abi: (await deployments.get("SinglePositionStrategy")).abi,
        address: newStrategyAddress,
    });

    const txs: string[] = [];
    const adminRole = await baseStrategy.ADMIN_ROLE();
    const adminDelegateRole = await baseStrategy.ADMIN_DELEGATE_ROLE();
    const operatorRole = await baseStrategy.OPERATOR();

    txs.push(
        strategy.interface.encodeFunctionData("grantRole", [
            adminDelegateRole,
            deployer,
        ])
    );

    txs.push(
        strategy.interface.encodeFunctionData("grantRole", [
            adminRole,
            mStrategyAdmin,
        ])
    );

    const strategyOperator = "0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E";
    if (strategyOperator.length > 0) {
        txs.push(
            strategy.interface.encodeFunctionData("grantRole", [
                operatorRole,
                strategyOperator,
            ])
        );
    }

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

    while (true) {
        try {
            await execute(
                deploymentName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS,
                },
                "multicall",
                txs
            );
            break;
        } catch {
            log("trying to do multicall again");
            continue;
        }
    }
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
