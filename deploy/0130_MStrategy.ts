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
    deploymentName: string,
    tickMin: any,
    tickMax: any
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

    const fee = 500;
    await setupCardinality(hre, tokens, fee);
    const params = [tokens, erc20Vault, moneyVault, fee, deployer];
    const address = await mStrategy.callStatic.createStrategy(...params);
    log(`CREATING STRATEGY`);
    const tx = await mStrategy.populateTransaction.createStrategy(...params, {
        ...TRANSACTION_GAS_LIMITS
    });
    const [operator] = await hre.ethers.getSigners();
    const txResp = await operator.sendTransaction(tx);
    log(
        `Sent transaction with hash \`${txResp.hash}\`. Waiting confirmation`
    );
    const receipt = await txResp.wait(1);
    log("Transaction confirmed");
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
        tickMin: tickMin,
        tickMax: tickMax,
        minTickRebalanceThreshold: BigNumber.from(600),
        tickNeighborhood: 50,
        tickIncrease: 10,
        erc20MoneyRatioD: BigNumber.from(10).pow(8),
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
    const adminDelegateRole = await read("ProtocolGovernance", "ADMIN_DELEGATE_ROLE");
    const operatorRole = await read("ProtocolGovernance", "OPERATOR");
    txs.push(
        mStrategyWethUsdc.interface.encodeFunctionData("grantRole", [
            adminRole,
            mStrategyAdmin
        ])
    );

    txs.push(
        mStrategyWethUsdc.interface.encodeFunctionData("grantRole", [
            adminDelegateRole,
            deployer
        ])
    );

    txs.push(
        mStrategyWethUsdc.interface.encodeFunctionData("grantRole", [
            operatorRole,
            deployer
        ])
    );

    txs.push(
        mStrategyWethUsdc.interface.encodeFunctionData("renounceRole", [
            adminRole,
            deployer
        ])
    );

    txs.push(
        mStrategyWethUsdc.interface.encodeFunctionData("renounceRole", [
            adminDelegateRole,
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
    deploymentName: any,
    tokenLimit: any,
    tickMin: any,
    tickMax: any
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

    log("SET UP ALL VAULTS");

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
        deploymentName,
        tickMin,
        tickMax
    );

    const strategy = await get(deploymentName);

    await combineVaults(
        hre,
        erc20VaultNft + 1,
        [erc20VaultNft, yearnVaultNft],
        strategy.address,
        mStrategyTreasury,
        {
            limits: tokens.map((_: any) => ethers.constants.MaxUint256),
            strategyPerformanceTreasuryAddress: mStrategyTreasury,
            tokenLimitPerAddress: tokenLimit,
            tokenLimit: tokenLimit,
            managementFee: BigNumber.from(10).pow(7).mul(2),
            performanceFee: BigNumber.from(10).pow(8).mul(2)
        }
    );

    const rootVaultAddress = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft + 1
    );

    const rootVault = await hre.ethers.getContractAt(
        "ERC20RootVault",
        rootVaultAddress
    )

    let tokensAmounts = [];

    for (let token of tokens) {
        const tokenContract = await hre.ethers.getContractAt("ERC20Token", token);
        const tx = await tokenContract.populateTransaction.approve(rootVaultAddress, BigNumber.from(2).pow(200));
        const [operator] = await hre.ethers.getSigners();
        const txResp = await operator.sendTransaction(tx);
        log(
            `Sent transaction with hash \`${txResp.hash}\`. Waiting confirmation`
        );
        const receipt = await txResp.wait(1);
        log("Transaction confirmed");
        let decimals = await tokenContract.decimals();
        tokensAmounts.push(BigNumber.from(10).pow(decimals / 2 + 1));
    }

    const mstrategy = await hre.ethers.getContractAt("MStrategy", strategy.address);
    log("Making first deposit", map((x) => x.toString(), tokensAmounts));
    await deployments.save(`${deploymentName}_RootVault`, {
        abi: (await deployments.get("ERC20RootVault")).abi,
        address: rootVaultAddress,
    });
    await execute(
        `${deploymentName}_RootVault`,
        {
            from: deployer,
            log: true,
            autoMine: true,
            ...TRANSACTION_GAS_LIMITS
        },
        "deposit",
        tokensAmounts,
        0,
        []
    )
    await rootVault.deposit(tokensAmounts, 0, []);
    log("Rebalancing...");
    const txs = [];
    txs.push(mstrategy.interface.encodeFunctionData("rebalance", [
        [0, 0],
        []
    ]));
    // await mstrategy.rebalance([0, 0], []);

    const operatorRole = await read("ProtocolGovernance", "OPERATOR");
    txs.push(mstrategy.interface.encodeFunctionData("renounceRole", [
        operatorRole,
        deployer
    ]));
    // await mstrategy.renounceRole(operatorRole, deployer);

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
    )
};

export const buildMStrategies: (kind: MoneyVault) => DeployFunction =
    (kind) => async (hre: HardhatRuntimeEnvironment) => {
        const { deployments, getNamedAccounts } = hre;
        const { weth, usdc, wbtc } = await getNamedAccounts();
        await deployMStrategy(hre, kind);

        for (let [tokens, deploymentName, tokenLimit, tickMin, tickMax] of [
            [[weth, wbtc], `MStrategy${kind}_WETH_WBTC`, BigNumber.from(10).pow(13).mul(44), 255800, 256000],
            [[weth, usdc], `MStrategy${kind}_WETH_USDC`, BigNumber.from(10).pow(18), 200805, 201005],
        ]) {
            await buildMStrategy(hre, kind, tokens, deploymentName, tokenLimit, tickMin, tickMax);
        }
    };

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {};
export default func;
