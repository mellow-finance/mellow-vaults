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

const deploymentName = "PulseStrategyV2";
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
    await deploy("PulseStrategyV2Helper", {
        from: deployer,
        contract: "PulseStrategyV2Helper",
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
    await deploy(deploymentName, {
        from: deployer,
        contract: "PulseStrategyV2",
        args: [uniswapV3PositionManager],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};

const buildSinglePositionStrategy = async (
    hre: HardhatRuntimeEnvironment,
    tokens: string[],
    mutableParams: any
) => {
    const { deployments, getNamedAccounts } = hre;
    const { log, read, execute, get, deploy } = deployments;
    const { deployer, mStrategyTreasury, aggregationRouterV5, uniswapV3PositionManager } =
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

    const immutableParams = {
        router: aggregationRouterV5,
        erc20Vault: erc20Vault,
        uniV3Vault: uniV3Vault500,
        tokens: tokens,
    } as ImmutableParamsStruct;


    console.log("ImmutableParams:", immutableParams);
    console.log("MutableParams:", mutableParams);

    const strategy = await hre.ethers.getContract(deploymentName);
    const { address: proxyAddress } = await deploy("PulseStrategyV2ProxyWide", {
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



type ImmutableParamsStruct = {
    router: string;
    erc20Vault: string;
    uniV3Vault: string;
    tokens: string[];
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { weth, bob } = await getNamedAccounts();

    if (!bob) return;
    await deployStrategy(hre);
    return;
    await buildSinglePositionStrategy(hre, [weth, bob], {
        priceImpactD6: 0,
        defaultIntervalWidth: 4200,
        maxPositionLengthInTicks: 10000,
        maxDeviationForVaultPool: 50,
        timespanForAverageTick: 60,
        neighborhoodFactorD: 10 ** 7 * 15,
        extensionFactorD: 10 ** 9 * 2,
        swapSlippageD: 10 ** 7,
        swappingAmountsCoefficientD: 10 ** 7,
        minSwapAmounts: [BigNumber.from(10).pow(13), BigNumber.from(10).pow(15)]
    });
}

export default func;

func.tags = ["PulseStrategyV2", "polygon"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "UniV3VaultGovernance",
    "ERC20RootVaultGovernance",
];
