import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {
    combineVaults,
    MAIN_NETWORKS,
    setupVault,
    toObject,
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
    const { deployer, uniswapV3Factory } =
        await getNamedAccounts();

    const factory = await hre.ethers.getContractAt(
        "IUniswapV3Factory",
        uniswapV3Factory
    );
    const pool = await hre.ethers.getContractAt(
        "IUniswapV3Pool",
        await factory.getPool(tokens[0], tokens[1], fee)
    );
    await pool.increaseObservationCardinalityNext(100);
}

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
    });
};

const setupStrategy = async (
    hre: HardhatRuntimeEnvironment,
    kind: MoneyVault,
    erc20Vault: string,
    moneyVault: string
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

    const tokens = [weth, usdc].map((x) => x.toLowerCase()).sort();
    const fee = 3000;
    await setupCardinality(hre, tokens, fee);
    const params = [tokens, erc20Vault, moneyVault, fee, mStrategyAdmin];
    const address = await mStrategy.callStatic.createStrategy(...params);
    if (!(await deployments.getOrNull(`${mStrategyName}_WETH_USDC`))) {
        return;
    }
    await mStrategy.createStrategy(...params);
    await deployments.save(`${mStrategyName}_WETH_USDC`, {
        abi: (await deployments.get(mStrategyName)).abi,
        address,
    });
    const mStrategyWethUsdc = await hre.ethers.getContractAt(
        mStrategyName,
        address
    );

    log("Setting Strategy params");

    const oracleParams = {
        oracleObservationDelta: 15,
        maxTickDeviation: 50,
        maxSlippageD: Math.round(0.1 * 10 ** 9),
    };
    const ratioParams = {
        tickMin: 198240 - 5000,
        tickMax: 198240 + 5000,
        erc20MoneyRatioD: Math.round(0.1 * 10 ** 9),
        minErc20MoneyRatioDeviationD: Math.round(0.01 * 10 ** 9),
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
    await execute(
        `${mStrategyName}_WETH_USDC`,
        {
            from: deployer,
            log: true,
            autoMine: true,
        },
        "multicall",
        txs
    );
};

export const buildMStrategy: (kind: MoneyVault) => DeployFunction =
    (kind) => async (hre: HardhatRuntimeEnvironment) => {
        const { deployments, getNamedAccounts } = hre;
        const { log, execute, read, get } = deployments;
        const { deployer, mStrategyTreasury, weth, usdc } =
            await getNamedAccounts();
        await deployMStrategy(hre, kind);

        const tokens = [weth, usdc].map((t) => t.toLowerCase()).sort();
        // const startNft = 1;
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

        const strategy = await get(`MStrategy${kind}`);

        await combineVaults(
            hre,
            erc20VaultNft + 1,
            [erc20VaultNft, yearnVaultNft],
            strategy.address,
            mStrategyTreasury
        );
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
        await setupStrategy(hre, kind, erc20Vault, moneyVault);
    };

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {};
export default func;
