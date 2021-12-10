import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { equals } from "ramda";
import { setupVault, toObject } from "./000_utils";

const deployMStrategy = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, log, execute, read, get } = deployments;
    const { deployer, mStrategyAdmin } = await getNamedAccounts();

    await deploy("MStrategyProxyAdmin", {
        from: deployer,
        contract: "DefaultProxyAdmin",
        args: [],
        log: true,
        autoMine: true,
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
    const mStrategyDeployment = await deploy("MStrategy", {
        from: deployer,
        args: [mStrategyAdmin],
        log: true,
        autoMine: true,
    });
    await deploy("MStrategyProxy", {
        from: deployer,
        contract: "DefaultProxy",
        args: [mStrategyDeployment.address, mStrategyAdmin, []],
        log: true,
        autoMine: true,
    });
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read, get } = deployments;
    const { deployer, mStrategyTreasury, weth, wbtc } =
        await getNamedAccounts();
    const gatewayVaultGovernance = await get("GatewayVaultGovernance");
    const lpIssuerVaultGovernance = await get("LpIssuerGovernance");
    await deployMStrategy(hre);

    const tokens = [weth, wbtc].map((t) => t.toLowerCase()).sort();
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

    const strategy = await get("MStrategyProxy");

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
};

export default func;
func.tags = ["MStrategy"];
