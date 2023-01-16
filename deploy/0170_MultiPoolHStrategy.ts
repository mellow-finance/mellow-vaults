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
import { ethers } from "hardhat";

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

    await deploy("MultiPoolHStrategyRebalancer", {
        from: deployer,
        contract: "MultiPoolHStrategyRebalancer",
        args: [uniswapV3PositionManager],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });

    await deploy("MultiPoolHStrategy", {
        from: deployer,
        contract: "MultiPoolHStrategy",
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};

const createMultiPoolHStrategy = async function (
    hre: HardhatRuntimeEnvironment,
    constructorParams: MultiPoolStrategyConstructorParams,
    deploymentName: string,
    vaults: VaultsAddresses,
    mutableParams: MutableParamsStruct
) {
    const { deployments, getNamedAccounts } = hre;
    const { execute } = deployments;
    const { deployer } = await getNamedAccounts();

    const { address: rebalancer } = await hre.ethers.getContract(
        "MultiPoolHStrategyRebalancer"
    );

    const baseStrategy = await hre.ethers.getContract("MultiPoolHStrategy");

    const immutableParams = {
        tokens: [constructorParams.token0, constructorParams.token1],
        erc20Vault: vaults.erc20Vault,
        moneyVault: vaults.moneyVault,
        router: constructorParams.router,
        rebalancer: rebalancer,
        uniV3Vaults: vaults.uniV3Vaults,
        tickSpacing: constructorParams.tickSpacing,
    } as ImmutableParamsStruct;
    const address = await baseStrategy.callStatic.createStrategy(
        immutableParams,
        mutableParams,
        deployer
    );
    await execute(
        "MultiPoolHStrategy",
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

    await deployments.save(deploymentName, {
        abi: (await deployments.get("MultiPoolHStrategy")).abi,
        address,
    });

    const createdStrategy = await hre.ethers.getContractAt(
        "MultiPoolHStrategy",
        address
    );

    return createdStrategy;
};

const setupStrategy = async (
    hre: HardhatRuntimeEnvironment,
    deploymentName: string,
    constructorParams: MultiPoolStrategyConstructorParams,
    mutableParams: MutableParamsStruct,
    vaults: VaultsAddresses
) => {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read } = deployments;
    const { deployer, mStrategyAdmin } = await getNamedAccounts();

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

    const strategy = await createMultiPoolHStrategy(
        hre,
        constructorParams,
        deploymentName,
        vaults,
        mutableParams
    );
    const txs: string[] = [];

    const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");
    const adminDelegateRole = await read(
        "ProtocolGovernance",
        "ADMIN_DELEGATE_ROLE"
    );
    const operatorRole = await read("ProtocolGovernance", "OPERATOR");

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

    const hStrategyOperator = "0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E";
    if (hStrategyOperator.length > 0) {
        txs.push(
            strategy.interface.encodeFunctionData("grantRole", [
                operatorRole,
                hStrategyOperator,
            ])
        );
    }

    // renounce roles
    txs.push(
        strategy.interface.encodeFunctionData("renounceRole", [
            operatorRole,
            deployer,
        ])
    );

    txs.push(
        strategy.interface.encodeFunctionData("renounceRole", [
            adminDelegateRole,
            deployer,
        ])
    );

    txs.push(
        strategy.interface.encodeFunctionData("renounceRole", [
            adminRole,
            deployer,
        ])
    );

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

const buildMultiPoolHStrategy = async (
    hre: HardhatRuntimeEnvironment,
    tokens: string[],
    constructorParams: MultiPoolStrategyConstructorParams,
    mutableParams: MutableParamsStruct,
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

    const vaults: VaultsAddresses = {
        erc20Vault: erc20Vault,
        moneyVault: moneyVault,
        uniV3Vaults: [uniV3Vault500, uniV3Vault3000],
    };

    const deploymentName =
        "MultiPoolHStrategy_" +
        (moneyGovernance[0] == "A" ? "Aave" : "Yearn") +
        "_" +
        ("SwapPoolFee" + mutableParams.swapPool) +
        "_" +
        ("UniV3VaultsCount" + vaults.uniV3Vaults.length.toString());

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
    const immutableParams = await strategy.immutableParams();
    await combineVaults(
        hre,
        erc20RootVaultNft,
        [erc20VaultNft, moneyVaultNft, uniV3VaultNft500, uniV3VaultNft3000],
        immutableParams.rebalancer,
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

type MutableParamsStruct = {
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

type ImmutableParamsStruct = {
    tokens: string[];
    erc20Vault: string;
    moneyVault: string;
    router: string;
    rebalancer: string;
    uniV3Vaults: string[];
    tickSpacing: BigNumberish;
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { weth, usdc, wbtc, uniswapV3Router } = await getNamedAccounts();

    await deployStrategy(hre);
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
        } as MutableParamsStruct,
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
