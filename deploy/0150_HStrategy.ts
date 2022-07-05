import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {
    combineVaults,
    setupVault,
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
    const { getNamedAccounts } = hre;
    const { uniswapV3Factory } = await getNamedAccounts();

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

const deployHStrategy = async function (
    hre: HardhatRuntimeEnvironment,
    kind: MoneyVault
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer, uniswapV3Router, uniswapV3PositionManager } =
        await getNamedAccounts();

    await deploy(`HStrategy${kind}`, {
        from: deployer,
        contract: "HStrategy",
        args: [uniswapV3PositionManager, uniswapV3Router],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};

const deployUniV3Helper = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    await deploy("UniV3Helper", {
        from: deployer,
        contract: "UniV3Helper",
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};

const deployHStrategyHelper = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    await deploy("HStrategyHelper", {
        from: deployer,
        contract: "HStrategyHelper",
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};

const setupStrategy = async (
    hre: HardhatRuntimeEnvironment,
    kind: MoneyVault,
    uniV3Helper: string,
    hStrategyHelper: string,
    erc20Vault: string,
    moneyVault: string,
    uniV3Vault: string,
    tokens: string[],
    deploymentName: string
) => {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read } = deployments;

    const { deployer, mStrategyAdmin } = await getNamedAccounts();
    const hStrategyName = `HStrategy${kind}`;
    const { address: hStrategyAddress } = await deployments.get(hStrategyName);
    const hStrategy = await hre.ethers.getContractAt(
        "HStrategy",
        hStrategyAddress
    );

    const fee = 3000;
    await setupCardinality(hre, tokens, fee);
    const params = [
        tokens,
        erc20Vault,
        moneyVault,
        uniV3Vault,
        fee,
        deployer,
        uniV3Helper,
        hStrategyHelper,
    ];
    const address = await hStrategy.callStatic.createStrategy(...params);
    await hStrategy.createStrategy(...params);
    await deployments.save(deploymentName, {
        abi: (await deployments.get(hStrategyName)).abi,
        address,
    });
    const hStrategyWethUsdc = await hre.ethers.getContractAt(
        "HStrategy",
        address
    );

    log("Setting Strategy params");

    const startegyParams = {
        widthCoefficient: 15,
        widthTicks: 60,
        oracleObservationDelta: 150,
        erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5), // 5%
        minToken0ForOpening: BigNumber.from(10).pow(6),
        minToken1ForOpening: BigNumber.from(10).pow(6),
        globalLowerTick: 23400,
        globalUpperTick: 29700,
        tickNeighborhood: 0,
        maxTickDeviation: 100,
        simulateUniV3Interval: false, // simulating uniV2 Interval
    };
    const txs: string[] = [];
    txs.push(
        hStrategyWethUsdc.interface.encodeFunctionData("updateStrategyParams", [
            startegyParams,
        ])
    );

    log(
        `Strategy Params:`,
        map((x) => x.toString(), startegyParams)
    );

    log("Transferring ownership to mStrategyAdmin");

    const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");
    txs.push(
        hStrategyWethUsdc.interface.encodeFunctionData("grantRole", [
            adminRole,
            mStrategyAdmin,
        ])
    );
    txs.push(
        hStrategyWethUsdc.interface.encodeFunctionData("renounceRole", [
            adminRole,
            deployer,
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

const buildHStrategy = async (
    hre: HardhatRuntimeEnvironment,
    kind: MoneyVault,
    tokens: any,
    deploymentName: any
) => {
    const { deployments, getNamedAccounts } = hre;
    const { read, get } = deployments;
    const { deployer, mStrategyTreasury } = await getNamedAccounts();
    tokens = tokens.map((t: string) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let erc20VaultNft = startNft;
    let yearnVaultNft = startNft + 1;
    let uniV3VaultNft = startNft + 2;
    let erc20RootVaultNft = startNft + 3;
    const moneyGovernance =
        kind === "Aave" ? "AaveVaultGovernance" : "YearnVaultGovernance";

    const { address: uniV3Helper } = await hre.ethers.getContract(
        "UniV3Helper"
    );
    const { address: hStrategyHelper } = await hre.ethers.getContract(
        "HStrategyHelper"
    );

    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    await setupVault(hre, yearnVaultNft, moneyGovernance, {
        createVaultArgs: [tokens, deployer],
    });

    await setupVault(hre, uniV3VaultNft, "UniV3VaultGovernance", {
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
        yearnVaultNft
    );
    const uniV3Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        uniV3VaultNft
    );
    await setupStrategy(
        hre,
        kind,
        uniV3Helper,
        hStrategyHelper,
        erc20Vault,
        moneyVault,
        uniV3Vault,
        tokens,
        deploymentName
    );

    const strategy = await get(deploymentName);

    await combineVaults(
        hre,
        erc20RootVaultNft,
        [erc20VaultNft, yearnVaultNft, uniV3VaultNft],
        strategy.address,
        mStrategyTreasury
    );
};

export const buildHStrategies: (kind: MoneyVault) => DeployFunction =
    (kind) => async (hre: HardhatRuntimeEnvironment) => {
        const { getNamedAccounts } = hre;
        const { weth, usdc, wbtc } = await getNamedAccounts();
        await deployHStrategy(hre, kind);
        await deployUniV3Helper(hre);
        await deployHStrategyHelper(hre);

        for (let [tokens, deploymentName] of [
            [[weth, usdc], `HStrategy${kind}_WETH_USDC`],
            [[weth, wbtc], `HStrategy${kind}_WETH_WBTC`],
        ]) {
            await buildHStrategy(hre, kind, tokens, deploymentName);
        }
    };

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {};
export default func;
