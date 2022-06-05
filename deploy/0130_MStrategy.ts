import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {
    combineVaults,
    MAIN_NETWORKS,
    setupVault,
    toObject,
    TRANSACTION_GAS_LIMITS,
} from "./0000_utils";
import { BigNumber, ethers } from "ethers";
import { map } from "ramda";

type MoneyVault = "Aave" | "Yearn";

const setupCardinality = async function (
    hre: HardhatRuntimeEnvironment,
    tokens: string[],
    fee: 500 | 3000 | 10000
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, log, execute, read, get, getOrNull } = deployments;
    const { deployer, uniswapV3Factory } = await getNamedAccounts();

    const factory = await hre.ethers.getContractAt(
        "IUniswapV3Factory",
        uniswapV3Factory
    );
    const pool = await hre.ethers.getContractAt(
        "IUniswapV3Pool",
        await factory.getPool(tokens[0], tokens[1], fee)
    );
    await pool.increaseObservationCardinalityNext(100);
};

const deployMStrategy = async function (
    hre: HardhatRuntimeEnvironment,
    kind: MoneyVault
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, log, execute, read, get, getOrNull } = deployments;
    const { deployer, uniswapV3Router, uniswapV3PositionManager } =
        await getNamedAccounts();

    await deploy(`MStrategy${kind}`, {
        from: deployer,
        contract: "MStrategy",
        args: [uniswapV3PositionManager, uniswapV3Router],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};

const setupStrategy = async (
    hre: HardhatRuntimeEnvironment,
    kind: MoneyVault,
    erc20Vault: string,
    moneyVault: string,
    tokens: string[],
    deploymentName: string
) => {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, log, execute, read, get } = deployments;

    const {
        deployer,
        weth,
        usdc,
        uniswapV3Router,
        uniswapV3Factory,
        mStrategyAdmin,
    } = await getNamedAccounts();
    const mStrategyName = `MStrategy${kind}`;
    const { address: mStrategyAddress } = await deployments.get(mStrategyName);
    const mStrategy = await hre.ethers.getContractAt(
        "MStrategy",
        mStrategyAddress
    );

    const fee = 3000;
    await setupCardinality(hre, tokens, fee);
    const params = [tokens, erc20Vault, moneyVault, fee, deployer];
    const address = await mStrategy.callStatic.createStrategy(...params);
    await mStrategy.createStrategy(...params);
    await deployments.save(deploymentName, {
        abi: (await deployments.get(mStrategyName)).abi,
        address,
    });
    const mStrategyWethUsdc = await hre.ethers.getContractAt(
        "MStrategy",
        address
    );

    log("Setting Strategy params");

    const oracleParams = {
        oracleObservationDelta: 15 * 60,
        maxTickDeviation: 100,
        maxSlippageD: BigNumber.from(10).pow(9).div(100),
    };
    const ratioParams = {
        tickMin: 189324,
        tickMax: 207242,
        erc20MoneyRatioD: BigNumber.from(10).pow(8),
        minTickRebalanceThreshold: BigNumber.from(1200),
        tickNeighborhood: 50,
        tickIncrease: 10,
        minErc20MoneyRatioDeviation0D: BigNumber.from(10).pow(9),
        minErc20MoneyRatioDeviation1D: BigNumber.from(10).pow(9),
    };
    const txs = [];
    txs.push(
        mStrategyWethUsdc.interface.encodeFunctionData("setOracleParams", [
            oracleParams,
        ])
    );
    txs.push(
        mStrategyWethUsdc.interface.encodeFunctionData("setRatioParams", [
            ratioParams,
        ])
    );

    log(
        `Oracle Params:`,
        map((x) => x.toString(), oracleParams)
    );
    log(
        `Ratio Params:`,
        map((x) => x.toString(), ratioParams)
    );

    log("Transferring ownership to mStrategyAdmin");

    const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");
    txs.push(
        mStrategyWethUsdc.interface.encodeFunctionData("grantRole", [
            adminRole,
            mStrategyAdmin
        ])
    );

    txs.push(
        mStrategyWethUsdc.interface.encodeFunctionData("renounceRole", [
            adminRole,
            deployer
        ])
    );

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
};

const buildMStrategy = async (
    hre: HardhatRuntimeEnvironment,
    kind: MoneyVault,
    tokens: any,
    deploymentName: any
) => {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read, get } = deployments;
    const { deployer, mStrategyTreasury } = await getNamedAccounts();
    tokens = tokens.map((t: string) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;
    let yearnVaultNft = startNft;
    let erc20VaultNft = startNft + 1;
    const moneyGovernance =
        kind === "Aave" ? "AaveVaultGovernance" : "YearnVaultGovernance";
    await setupVault(hre, yearnVaultNft, moneyGovernance, {
        createVaultArgs: [tokens, deployer],
    });
    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );
    const moneyVault = await read(
        "VaultRegistry",
        "vaultForNft",
        yearnVaultNft
    );
    await setupStrategy(
        hre,
        kind,
        erc20Vault,
        moneyVault,
        tokens,
        deploymentName
    );

    const strategy = await get(deploymentName);

    await combineVaults(
        hre,
        erc20VaultNft + 1,
        [erc20VaultNft, yearnVaultNft],
        strategy.address,
        mStrategyTreasury
    );
};

export const buildMStrategies: (kind: MoneyVault) => DeployFunction =
    (kind) => async (hre: HardhatRuntimeEnvironment) => {
        const { deployments, getNamedAccounts } = hre;
        const { weth, usdc, wbtc } = await getNamedAccounts();
        await deployMStrategy(hre, kind);

        for (let [tokens, deploymentName] of [
            [[weth, usdc], `MStrategy${kind}_WETH_USDC`],
            [[weth, wbtc], `MStrategy${kind}_WETH_WBTC`],
        ]) {
            await buildMStrategy(hre, kind, tokens, deploymentName);
        }
    };

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {};
export default func;
