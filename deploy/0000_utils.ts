import { PopulatedTransaction } from "@ethersproject/contracts";
import { TransactionReceipt } from "@ethersproject/abstract-provider";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import {
    equals,
    filter,
    fromPairs,
    keys,
    KeyValuePair,
    map,
    pipe,
} from "ramda";
import { read } from "fs";
import { deployments } from "hardhat";
import { BigNumber, BigNumberish, ethers } from "ethers";

export const ALL_NETWORKS = [
    "hardhat",
    "localhost",
    "mainnet",
    "kovan",
    "arbitrum",
    "optimism",
    "bsc",
    "avalance",
    "polygon",
    "fantom",
];
export const MAIN_NETWORKS = ["hardhat", "localhost", "mainnet", "kovan"];

export const setupVault = async (
    hre: HardhatRuntimeEnvironment,
    expectedNft: number,
    contractName: string,
    {
        createVaultArgs,
        delayedStrategyParams,
        strategyParams,
        delayedProtocolPerVaultParams,
    }: {
        createVaultArgs: any[];
        delayedStrategyParams?: { [key: string]: any };
        strategyParams?: { [key: string]: any };
        delayedProtocolPerVaultParams?: { [key: string]: any };
    }
) => {
    delayedStrategyParams ||= {};
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read } = deployments;
    const { deployer, admin } = await getNamedAccounts();
    const currentNft = await read("VaultRegistry", "vaultsCount");
    if (currentNft <= expectedNft) {
        log(`Deploying ${contractName.replace("Governance", "")}...`);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "createVault",
            ...createVaultArgs
        );
        log(`Done, nft = ${expectedNft}`);
    } else {
        log(
            `${contractName.replace(
                "Governance",
                ""
            )} with nft = ${expectedNft} already deployed`
        );
    }
    if (strategyParams) {
        const currentParams = await read(
            contractName,
            "strategyParams",
            expectedNft
        );

        if (!equals(strategyParams, currentParams)) {
            log(`Setting Strategy params for ${contractName}`);
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                },
                "setStrategyParams",
                expectedNft,
                strategyParams
            );
        }
    }
    let strategyTreasury;
    try {
        const data = await read(
            contractName,
            "delayedStrategyParams",
            expectedNft
        );
        strategyTreasury = data.strategyTreasury;
    } catch {
        return;
    }

    if (strategyTreasury !== delayedStrategyParams.strategyTreasury) {
        log(`Setting delayed strategy params for ${contractName}`);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "stageDelayedStrategyParams",
            expectedNft,
            delayedStrategyParams
        );
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "commitDelayedStrategyParams",
            expectedNft
        );
    }
    if (delayedProtocolPerVaultParams) {
        const params = await read(
            contractName,
            "delayedProtocolPerVaultParams",
            expectedNft
        );
        if (!equals(toObject(params), delayedProtocolPerVaultParams)) {
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                },
                "stageDelayedProtocolPerVaultParams",
                expectedNft,
                delayedProtocolPerVaultParams
            );
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                },
                "commitDelayedProtocolPerVaultParams",
                expectedNft
            );
        }
    }
};

export const combineVaults = async (
    hre: HardhatRuntimeEnvironment,
    expectedNft: number,
    nfts: number[],
    strategyAddress: string,
    strategyTreasuryAddress: string,
    options?: {
        limits?: BigNumberish[];
        strategyPerformanceTreasuryAddress?: string;
        tokenLimitPerAddress: BigNumberish;
        managementFee: BigNumberish;
        performanceFee: BigNumberish;
    }
): Promise<void> => {
    if (nfts.length === 0) {
        throw `Trying to combine 0 vaults`;
    }
    const { deployer } = await hre.getNamedAccounts();
    const firstNft = nfts[0];
    const firstAddress = await deployments.read(
        "VaultRegistry",
        "vaultForNft",
        firstNft
    );
    const vault = await hre.ethers.getContractAt("IVault", firstAddress);
    const tokens = await vault.vaultTokens();
    const coder = hre.ethers.utils.defaultAbiCoder;

    const {
        limits = tokens.map((_: any) => ethers.constants.MaxUint256),
        strategyPerformanceTreasuryAddress = strategyTreasuryAddress,
        tokenLimitPerAddress = ethers.constants.MaxUint256,
        managementFee = 2 * 10 ** 9,
        performanceFee = 20 * 10 ** 9,
    } = options || {};

    await setupVault(hre, expectedNft, "ERC20RootVaultGovernance", {
        createVaultArgs: [
            tokens,
            strategyAddress,
            nfts,
            "MStrategy LP Token",
            "MSLP",
            deployer,
        ],
        delayedStrategyParams: {
            strategyTreasury: strategyTreasuryAddress,
            strategyPerformanceTreasury: strategyPerformanceTreasuryAddress,
            managementFee: BigNumber.from(managementFee),
            performanceFee: BigNumber.from(performanceFee),
        },
        strategyParams: {
            tokenLimitPerAddress: BigNumber.from(tokenLimitPerAddress),
        },
    });
    const rootVault = await deployments.read(
        "VaultRegistry",
        "vaultForNft",
        expectedNft
    );
    await deployments.execute(
        "VaultRegistry",
        { from: deployer, autoMine: true },
        "transferFrom(address,address,uint256)",
        deployer,
        rootVault,
        expectedNft
    );
};

const deployMStrategy = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, log, execute, read, get } = deployments;
    const { deployer, mStrategyAdmin } = await getNamedAccounts();

    const proxyAdminDeployment = await deploy("MStrategyProxyAdmin", {
        from: deployer,
        contract: "DefaultProxyAdmin",
        args: [],
        log: true,
        autoMine: true,
    });

    const mStrategyDeployment = await deploy("MStrategy", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
        proxy: {
            execute: { init: { methodName: "init", args: [deployer] } },
            proxyContract: "DefaultProxy",
            viaAdminContract: {
                name: "MStrategyProxyAdmin",
                artifact: "DefaultProxyAdmin",
            },
        },
    });
    await execute(
        "MStrategyProxyAdmin",
        {
            from: deployer,
            log: true,
            autoMine: true,
        },
        "transferOwnership",
        mStrategyAdmin
    );
};

export const toObject = (obj: any) =>
    pipe(
        keys,
        filter((x: string) => isNaN(parseInt(x))),
        map((x) => [x, obj[x]] as KeyValuePair<string, any>),
        fromPairs
    )(obj);

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {};
export default func;
