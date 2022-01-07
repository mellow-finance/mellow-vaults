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

const deployMStrategy = async function (
    hre: HardhatRuntimeEnvironment,
    kind: MoneyVault
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, log, execute, read, get, getOrNull } = deployments;
    const { deployer, mStrategyAdmin } = await getNamedAccounts();

    const proxyAdminDeployment = await deploy(`MStrategy${kind}ProxyAdmin`, {
        from: deployer,
        contract: "DefaultProxyAdmin",
        args: [],
        log: true,
        autoMine: true,
    });

    const mStrategyDeployment = await getOrNull(
        `MStrategy${kind}_Implementation`
    );
    if (!mStrategyDeployment) {
        await deploy(`MStrategy${kind}`, {
            from: deployer,
            contract: "MStrategy",
            args: [],
            log: true,
            autoMine: true,
            proxy: {
                execute: { init: { methodName: "init", args: [deployer] } },
                proxyContract: "DefaultProxy",
                viaAdminContract: {
                    name: `MStrategy${kind}ProxyAdmin`,
                    artifact: "DefaultProxyAdmin",
                },
            },
        });
    }
    const owner = await read(`MStrategy${kind}ProxyAdmin`, "owner");
    if (owner != mStrategyAdmin) {
        await execute(
            `MStrategy${kind}ProxyAdmin`,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "transferOwnership",
            mStrategyAdmin
        );
    }
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

    const tokens = [weth, usdc].map((x) => x.toLowerCase()).sort();

    const vaultCount = await read(mStrategyName, "vaultCount");
    if (vaultCount.toNumber() === 0) {
        log("Setting Strategy params");
        const uniFactory = await hre.ethers.getContractAt(
            "IUniswapV3Factory",
            uniswapV3Factory
        );
        const uniV3Pool = await uniFactory.getPool(tokens[0], tokens[1], 3000);
        const immutableParams = {
            token0: tokens[0],
            token1: tokens[1],
            uniV3Pool,
            uniV3Router: uniswapV3Router,
            erc20Vault,
            moneyVault,
        };
        const params = {
            oraclePriceTimespan: 1800,
            oracleLiquidityTimespan: 1800,
            liquidToFixedRatioX96: BigNumber.from(2).pow(96 - 2),
            sqrtPMinX96: BigNumber.from(
                Math.round((1 / Math.sqrt(3000)) * 10 ** 6 * 2 ** 20)
            ).mul(BigNumber.from(2).pow(76)),
            sqrtPMaxX96: BigNumber.from(
                Math.round((1 / Math.sqrt(5000)) * 10 ** 6 * 2 ** 20)
            ).mul(BigNumber.from(2).pow(76)),
            tokenRebalanceThresholdX96: BigNumber.from(
                Math.round(1.1 * 2 ** 20)
            ).mul(BigNumber.from(2).pow(76)),
            poolRebalanceThresholdX96: BigNumber.from(
                Math.round(1.1 * 2 ** 20)
            ).mul(BigNumber.from(2).pow(76)),
        };
        log(
            `Immutable Params:`,
            map((x) => x.toString(), immutableParams)
        );
        log(
            `Params:`,
            map((x) => x.toString(), params)
        );
        await execute(
            mStrategyName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "addVault",
            immutableParams,
            params
        );
    }
    const adminRole = await read(mStrategyName, "ADMIN_ROLE");
    const deployerIsAdmin = await read(mStrategyName, "isAdmin", deployer);
    if (deployerIsAdmin) {
        await execute(
            mStrategyName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "grantRole",
            adminRole,
            mStrategyAdmin
        );
        await execute(
            mStrategyName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "renounceRole",
            adminRole,
            deployer
        );
    }
};

export const buildMStrategy: (kind: MoneyVault) => DeployFunction =
    (kind) => async (hre: HardhatRuntimeEnvironment) => {
        const { deployments, getNamedAccounts } = hre;
        const { log, execute, read, get } = deployments;
        const { deployer, mStrategyTreasury, weth, usdc } =
            await getNamedAccounts();
        await deployMStrategy(hre, kind);

        const tokens = [weth, usdc].map((t) => t.toLowerCase()).sort();
        const startNft = 1;
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
