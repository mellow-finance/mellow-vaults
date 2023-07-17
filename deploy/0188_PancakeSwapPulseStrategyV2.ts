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

const deploymentName = "PancakeSwapPulseStrategyV2";
const deployStrategy = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer, pancakePositionManager } = await getNamedAccounts();

    await deploy("PancakeSwapHelper", {
        from: deployer,
        contract: "PancakeSwapHelper",
        args: [pancakePositionManager],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
    await deploy("PancakeSwapPulseV2Helper", {
        from: deployer,
        contract: "PancakeSwapPulseV2Helper",
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
    await deploy(deploymentName, {
        from: deployer,
        contract: "PancakeSwapPulseStrategyV2",
        args: [pancakePositionManager],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};

const buildStrategy = async (
    hre: HardhatRuntimeEnvironment,
    tokens: string[]
) => {
    const { deployments, getNamedAccounts } = hre;
    const { log, read, execute, get, deploy } = deployments;
    const { deployer, mStrategyTreasury, weth, mStrategyAdmin, aggregationRouterV5 } =
        await getNamedAccounts();

    tokens = tokens.map((t: string) => t.toLowerCase()).sort();
    const startNft = (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let erc20VaultNft = startNft;
    let pancakeSwapVaultNft = startNft + 1;
    let erc20RootVaultNft = startNft + 2;

    const { address: pancakeSwapHelper } = await hre.ethers.getContract(
        "PancakeSwapHelper"
    );

    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );

    await setupVault(hre, pancakeSwapVaultNft, "PancakeSwapVaultGovernance", {
        createVaultArgs: [tokens, deployer, 500, pancakeSwapHelper, '0x556B9306565093C855AEA9AE92A594704c2Cd59e', erc20Vault],
        delayedStrategyParams: [2],
    });

    await execute(
        "PancakeSwapVaultGovernance",
        {
            from: deployer,
            log: true,
            autoMine: true,
            ...TRANSACTION_GAS_LIMITS,
        },
        "setStrategyParams",
        pancakeSwapVaultNft,
        {
            swapSlippageD: BigNumber.from(10).pow(7).mul(5),
            poolForSwap: '0x517F451b0A9E1b87Dc0Ae98A05Ee033C3310F046',
            cake: '0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898',
            underlyingToken: weth,
            smartRouter: "0x678aa4bf4e210cf2166753e054d5b7c31cc7fa86",
            averageTickTimespan: 30
        }
    );

    const pancakeSwapVault = await read(
        "VaultRegistry",
        "vaultForNft",
        pancakeSwapVaultNft
    );

    const strategy = await hre.ethers.getContract(deploymentName);  
    const { address: proxyAddress } = await deploy("PancakeSwapPulseStrategyV2_WETH_USDC", {
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
    for (let nft of [erc20VaultNft, pancakeSwapVaultNft]) {
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
        [erc20VaultNft, pancakeSwapVaultNft],
        proxyAddress,
        mStrategyTreasury
    );

    const proxyStrategy = await hre.ethers.getContractAt(deploymentName, proxyAddress);  
    
    await proxyStrategy.initialize(
        {
            erc20Vault: erc20Vault,
            pancakeSwapVault: pancakeSwapVault,
            router: aggregationRouterV5,
            tokens: tokens,
        },
        deployer
    );

    await proxyStrategy.updateMutableParams({
        priceImpactD6: 0,
        defaultIntervalWidth: 4200,
        maxPositionLengthInTicks: 10000,
        maxDeviationForVaultPool: 100,
        timespanForAverageTick: 30,
        neighborhoodFactorD: 1e9,
        extensionFactorD: 1e8,
        swapSlippageD: 1e7,
        swappingAmountsCoefficientD: 1e7,
        minSwapAmounts: [BigNumber.from(10).pow(15).mul(5), BigNumber.from(10).pow(7)]
    });

    await proxyStrategy.updateDesiredAmounts(
        {amount0Desired: BigNumber.from(10 ** 9), amount1Desired: BigNumber.from(10).pow(6)}
    );

    const adminRole = await proxyStrategy.ADMIN_ROLE();
    await proxyStrategy.grantRole(
        adminRole,
        mStrategyAdmin
    );
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { weth, usdt } = await getNamedAccounts();

    await deployStrategy(hre);
    return;
    await buildStrategy(hre, [weth, usdt]);
}

export default func;

func.tags = ["PancakeSwapPulseStrategyV2", "mainnet"];
func.dependencies = [
    "VaultRegistry",
    "ERC20VaultGovernance",
    "PancakeSwapVaultGovernance",
    "ERC20RootVaultGovernance",
];
