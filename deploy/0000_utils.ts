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
import { deployments } from "hardhat";
import { BigNumber, BigNumberish, ethers } from "ethers";

export const ALLOWED_APPROVE_LIST = {
    mainnet: {
        uniV3: [
            "0x8ad599c3a0ff1de082011efddc58f1908eb6e6d8", // USDC-ETH 0.3%
            "0xcbcdf9626bc03e24f779434178a73a0b4bad62ed", // WBTC-ETH 0.3%
            "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640", // USDC-ETH 0.05%
            "0x99ac8ca7087fa4a2a1fb6357269965a2014abc35", // WBTC-USDC 0.3%
        ],
        uniV2: [
            "0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc", // USDC-ETH
            "0xbb2b8038a1640196fbe3e38816f3e67cba72d940", // WBTC-ETH
        ],
        curve: [
            "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7", // USDC-DAI
            "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022", // ETH-STETH
        ],
        cowswap: ["0xC92E8bdf79f0507f65a392b0ab4667716BFE0110"],
    },
};

export const PRIVATE_VAULT = true;

const ALLOW_ALL_REGISTER_VAULT = 0;
export const ALLOW_ALL_CREATE_VAULT = 0;
const ALLOW_ALL_ERC20_TRANSFER = 0;
const ALLOW_ALL_ERC20_VAULT_TOKEN = 0;
const ALLOW_ALL_ERC20_APPROVE = 0;
const ALLOW_ALL_ERC20_APPROVE_RESTRICTED = 0;
const ALLOW_ALL_TRUSTED_STRATEGY = 0;

export const ALLOW_MASK =
    (ALLOW_ALL_REGISTER_VAULT << 1) +
    (ALLOW_ALL_CREATE_VAULT << 2) +
    (ALLOW_ALL_ERC20_TRANSFER << 3) +
    (ALLOW_ALL_ERC20_VAULT_TOKEN << 4) +
    (ALLOW_ALL_ERC20_APPROVE << 5) +
    (ALLOW_ALL_ERC20_APPROVE_RESTRICTED << 6) +
    (ALLOW_ALL_TRUSTED_STRATEGY << 7);

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
    "xdai",
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

        if (!equals(strategyParams, toObject(currentParams))) {
            log(`Setting Strategy params for ${contractName}`);
            log(strategyParams);
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
        log(delayedStrategyParams);
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
            log(
                `Setting delayed protocol per vault params for ${contractName}`
            );
            log(delayedProtocolPerVaultParams);

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
        tokenLimit: BigNumberish;
        managementFee: BigNumberish;
        performanceFee: BigNumberish;
    }
): Promise<void> => {
    if (nfts.length === 0) {
        throw `Trying to combine 0 vaults`;
    }
    const { log } = deployments;
    const { deployer, admin } = await hre.getNamedAccounts();
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
        tokenLimit = ethers.constants.MaxUint256,
        managementFee = 2 * 10 ** 7,
        performanceFee = 20 * 10 ** 7,
    } = options || {};

    await setupVault(hre, expectedNft, "ERC20RootVaultGovernance", {
        createVaultArgs: [tokens, strategyAddress, nfts, deployer],
        delayedStrategyParams: {
            strategyTreasury: strategyTreasuryAddress,
            strategyPerformanceTreasury: strategyPerformanceTreasuryAddress,
            managementFee: BigNumber.from(managementFee),
            performanceFee: BigNumber.from(performanceFee),
            privateVault: PRIVATE_VAULT,
        },
        strategyParams: {
            tokenLimitPerAddress: BigNumber.from(tokenLimitPerAddress),
            tokenLimit: BigNumber.from(tokenLimit),
        },
    });
    const rootVault = await deployments.read(
        "VaultRegistry",
        "vaultForNft",
        expectedNft
    );
    if (PRIVATE_VAULT) {
        const rootVaultContract = await hre.ethers.getContractAt(
            "ERC20RootVault",
            rootVault
        );
        const depositors = (await rootVaultContract.depositorsAllowlist()).map(
            (x: any) => x.toString()
        );
        if (!depositors.includes(admin)) {
            log("Adding admin to depositors");
            const tx =
                await rootVaultContract.populateTransaction.addDepositorsToAllowlist(
                    [admin]
                );
            const [operator] = await hre.ethers.getSigners();
            const txResp = await operator.sendTransaction(tx);
            log(
                `Sent transaction with hash \`${txResp.hash}\`. Waiting confirmation`
            );
            const receipt = await txResp.wait(1);
            log("Transaction confirmed");
        }
    }
    await deployments.execute(
        "VaultRegistry",
        { from: deployer, autoMine: true },
        "transferFrom(address,address,uint256)",
        deployer,
        rootVault,
        expectedNft
    );
};

export const toObject = (obj: any) =>
    pipe(
        keys,
        filter((x: string) => isNaN(parseInt(x))),
        map((x) => [x, obj[x]] as KeyValuePair<string, any>),
        fromPairs
    )(obj);

export class PermissionIdsLibrary {
    static REGISTER_VAULT: number = 1;
    static CREATE_VAULT: number = 2;
    static ERC20_TRANSFER: number = 3;
    static ERC20_VAULT_TOKEN = 4;
    static ERC20_APPROVE: number = 5;
    static ERC20_APPROVE_RESTRICTED: number = 6;
    static ERC20_TRUSTED_STRATEGY: number = 7;
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {};
export default func;
