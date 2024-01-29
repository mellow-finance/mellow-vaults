import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {
    combineVaults,
    setupVault,
    TRANSACTION_GAS_LIMITS,
} from "./0000_utils";
import { BigNumber } from "ethers";

const deploymentName = "KyberPulseStrategyV2";
const deployStrategy = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer, kyberPositionManager } = await getNamedAccounts();

    await deploy("KyberPulseStrategyV2Helper", {
        from: deployer,
        contract: "KyberPulseStrategyV2Helper",
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    await deploy(deploymentName, {
        from: deployer,
        contract: "KyberPulseStrategyV2",
        args: [kyberPositionManager],
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
    const { deployer, mStrategyTreasury, aggregationRouterV5 } =
        await getNamedAccounts();

    tokens = tokens.map((t: string) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let erc20VaultNft = startNft;
    let kyberVaultNft = startNft + 1;
    let erc20RootVaultNft = startNft + 2;

    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    await setupVault(hre, kyberVaultNft, "KyberVaultGovernance", {
        createVaultArgs: [tokens, deployer, 40],
        // strategyParams: [
        //     '0xBdEc4a045446F583dc564C0A227FFd475b329bf0', // farm address
        //     [
        //         '0x1c954e8fe737f99f68fa1ccda3e51ebdb291948c0003e82791bca1f2de4661ed88a30c99a7a9449aa84174000008b0b195aefa3650a6908f15cdac7d92f8a5791b0b'
        //     ], // paths
        //     117 // pool id
        // ],
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );

    const kyberVault = await read(
        "VaultRegistry",
        "vaultForNft",
        kyberVaultNft
    );

    const immutableParams = {
        router: aggregationRouterV5,
        erc20Vault: erc20Vault,
        kyberVault: kyberVault,
        mellowOracle: "0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836",
        tokens: tokens,
    };

    console.log("ImmutableParams:", immutableParams);
    console.log("MutableParams:", mutableParams);

    const strategy = await hre.ethers.getContract(deploymentName);
    const { address: proxyAddress } = await deploy("PulseStrategyV2Proxy", {
        from: deployer,
        contract: "TransparentUpgradeableProxy",
        args: [strategy.address, deployer, []],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    const erc20RootVaultGovernance = await get("ERC20RootVaultGovernance");
    for (let nft of [erc20VaultNft, kyberVaultNft]) {
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
        [erc20VaultNft, kyberVaultNft],
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

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { stMatic, bob } = await getNamedAccounts();

    if (!bob || true) return;
    await deployStrategy(hre);

    await buildSinglePositionStrategy(hre, [stMatic, bob], {
        priceImpactD6: 0,
        defaultIntervalWidth: 4200,
        maxPositionLengthInTicks: 10000,
        maxDeviationForVaultPool: 50,
        timespanForAverageTick: 60,
        neighborhoodFactorD: 10 ** 7 * 15,
        extensionFactorD: 10 ** 9 * 2,
        swapSlippageD: 10 ** 7,
        swappingAmountsCoefficientD: 10 ** 7,
        minSwapAmounts: [
            BigNumber.from(10).pow(15),
            BigNumber.from(10).pow(15),
        ],
    });
};

export default func;

func.tags = ["KyberPulseStrategyV2", "polygon"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "KyberVaultGovernance",
    "ERC20RootVaultGovernance",
];
