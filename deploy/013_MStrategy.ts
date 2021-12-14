import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { setupVault, toObject } from "./000_utils";
import { BigNumber, ethers } from "ethers";
import { map } from "ramda";

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

const setupStrategy = async (
    hre: HardhatRuntimeEnvironment,
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

    const tokens = [weth, usdc].map((x) => x.toLowerCase()).sort();
    const vaultCount = await read("MStrategy", "vaultCount");
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
            "MStrategy",
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
    const adminRole = await read("MStrategy", "ADMIN_ROLE");
    const deployerIsAdmin = await read("MStrategy", "isAdmin", deployer);
    if (deployerIsAdmin) {
        await execute(
            "MStrategy",
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
            "MStrategy",
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

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read, get } = deployments;
    const { deployer, mStrategyTreasury, weth, usdc } =
        await getNamedAccounts();
    const gatewayVaultGovernance = await get("GatewayVaultGovernance");
    const lpIssuerVaultGovernance = await get("LpIssuerGovernance");
    await deployMStrategy(hre);

    const tokens = [weth, usdc].map((t) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;
    const coder = hre.ethers.utils.defaultAbiCoder;
    let yearnVaultNft = 1;
    let erc20VaultNft = 2;
    let gatewayVaultNft = 3;
    let lpIssuerNft = 4;

    await setupVault(hre, yearnVaultNft, startNft, "YearnVaultGovernance", {
        deployOptions: [tokens, [], deployer],
    });
    await setupVault(hre, erc20VaultNft, startNft, "ERC20VaultGovernance", {
        deployOptions: [tokens, [], deployer],
    });
    const approvedGw = await read(
        "VaultRegistry",
        "isApprovedForAll",
        deployer,
        gatewayVaultGovernance.address
    );
    const approvedIssuer = await read(
        "VaultRegistry",
        "isApprovedForAll",
        deployer,
        lpIssuerVaultGovernance.address
    );
    if (!approvedGw) {
        log("Approving gateway vault governance");
        await execute(
            "VaultRegistry",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "setApprovalForAll",
            gatewayVaultGovernance.address,
            true
        );
    }
    if (!approvedIssuer) {
        log("Approving lp issuer governance");
        await execute(
            "VaultRegistry",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "setApprovalForAll",
            lpIssuerVaultGovernance.address,
            true
        );
    }

    const strategy = await get("MStrategy");

    await setupVault(hre, gatewayVaultNft, startNft, "GatewayVaultGovernance", {
        deployOptions: [
            tokens,
            coder.encode(["uint256[]"], [[yearnVaultNft, erc20VaultNft]]),
            strategy.address, // mStrategy
        ],

        delayedStrategyParams: {
            strategyTreasury: mStrategyTreasury,
            redirects: [erc20VaultNft, erc20VaultNft],
        },
        strategyParams: {
            limits: [
                hre.ethers.constants.MaxUint256,
                hre.ethers.constants.MaxUint256,
            ],
        },
    });

    await setupVault(hre, lpIssuerNft, startNft, "LpIssuerGovernance", {
        deployOptions: [
            tokens,
            coder.encode(
                ["uint256", "string", "string"],
                [gatewayVaultNft, "MStrategy LP Token", "MSLP"]
            ),
            deployer,
        ],
        delayedStrategyParams: {
            strategyTreasury: mStrategyTreasury,
            strategyPerformanceTreasury: mStrategyTreasury,
            managementFee: 2 * 10 ** 9,
            performanceFee: 20 * 10 ** 9,
        },
        strategyParams: {
            tokenLimitPerAddress: hre.ethers.constants.MaxUint256,
        },
    });
    const lpIssuer = await read("VaultRegistry", "vaultForNft", lpIssuerNft);
    await execute(
        "VaultRegistry",
        { from: deployer, autoMine: true },
        "safeTransferFrom(address,address,uint256)",
        deployer,
        lpIssuer,
        lpIssuerNft
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
    await setupStrategy(hre, erc20Vault, moneyVault);
};

export default func;
func.tags = ["MStrategy"];
