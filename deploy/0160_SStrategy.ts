import hre, { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {
    ALL_NETWORKS,
    combineVaults,
    MAIN_NETWORKS,
    setupVault,
    TRANSACTION_GAS_LIMITS,
} from "./0000_utils";
import { BigNumber } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, log, execute } = deployments;
    const {
        approver,
        deployer,
        strategyTreasury,
        strategyAdmin,
        uniswapV3Router,
        squeethController,
        strategyOperator
    } = await getNamedAccounts();
    
    let controllerWeth = await (await hre.ethers.getContractAt("IController", squeethController)).weth();
    const tokens = [controllerWeth];

    let vaultRegistry = await ethers.getContract("VaultRegistry");
    const startNft = (await vaultRegistry.vaultsCount()).toNumber() + 1;

    let erc20VaultNft = startNft;
    let squeethVaultNft = startNft + 1;
    let rootVaultNft = startNft + 2;

    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });
    await setupVault(hre, squeethVaultNft, "SqueethVaultGovernance", {
        createVaultArgs: [deployer],
    });

    const erc20Vault = await vaultRegistry.vaultForNft(erc20VaultNft);
    const squeethVault = await vaultRegistry.vaultForNft(squeethVaultNft);

    let rootVaultGovernance = await ethers.getContract("ERC20RootVaultGovernanceForCyclic");

    await deployments.execute(
        "VaultRegistry",
        { from: deployer, autoMine: true, ...TRANSACTION_GAS_LIMITS },
        "approve(address,uint256)",
        rootVaultGovernance.address,
        erc20VaultNft
    );
    await deployments.execute(
        "VaultRegistry",
        { from: deployer, autoMine: true, ...TRANSACTION_GAS_LIMITS },
        "approve(address,uint256)",
        rootVaultGovernance.address,
        squeethVaultNft
    );

    let strategyDeployParams = await deploy("SStrategy", {
        from: deployer,
        contract: "SStrategy",
        args: [
            controllerWeth,
            erc20Vault,
            squeethVault,
            uniswapV3Router,
            deployer],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });

    const sStrategy = await ethers.getContractAt("SStrategy", strategyDeployParams.address);
    
    await combineVaults(
        hre,
        rootVaultNft,
        [erc20VaultNft, squeethVaultNft],
        sStrategy.address,
        strategyTreasury,
        {
            limits: undefined,
            strategyPerformanceTreasuryAddress: strategyTreasury,
            tokenLimitPerAddress: BigNumber.from(10).pow(25),
            tokenLimit: BigNumber.from(10).pow(25),
            managementFee: 0,
            performanceFee: 0,
        }, 
        "CyclicRootVault"
    );
    
    const rootVaultAddress = await read(
        "VaultRegistry",
        "vaultForNft",
        rootVaultNft
    );
    let rootVault = await ethers.getContractAt("CyclicRootVault", rootVaultAddress);

    await (await rootVault.setCycleDuration(BigNumber.from(3600).mul(24).mul(5))).wait();
    
    const ADMIN_ROLE =
    "0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8"; // keccak256("admin)
    const ADMIN_DELEGATE_ROLE =
        "0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7"; // keccak256("admin_delegate")
    const OPERATOR_ROLE =
        "0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622"; // keccak256("operator")
    
    await (await sStrategy.grantRole(ADMIN_ROLE, strategyAdmin)).wait();
    await (await sStrategy.grantRole(ADMIN_DELEGATE_ROLE, strategyAdmin)).wait();
    await (await sStrategy.grantRole(ADMIN_DELEGATE_ROLE, deployer)).wait();
    await (await sStrategy.grantRole(OPERATOR_ROLE, strategyOperator)).wait();
    
    await (await sStrategy.setRootVault(
        rootVault.address
    )).wait();

    await (await sStrategy.updateStrategyParams({
        lowerHedgingThresholdD9: BigNumber.from(10).pow(8).mul(5),
        upperHedgingThresholdD9: BigNumber.from(10).pow(9).mul(2),
    })).wait();

    await (await sStrategy.updateLiquidationParams({
        lowerLiquidationThresholdD9: BigNumber.from(10).pow(7).mul(50), 
        upperLiquidationThresholdD9: BigNumber.from(10).pow(7).mul(180),
    })).wait();

    await (await sStrategy.updateOracleParams({
        maxTickDeviation: BigNumber.from(100),
        slippageD9: BigNumber.from(10).pow(7),
        oracleObservationDelta: BigNumber.from(15 * 60),
    })).wait();
    
    await (await sStrategy.revokeRole(ADMIN_DELEGATE_ROLE, deployer)).wait();
    await (await sStrategy.revokeRole(ADMIN_ROLE, deployer)).wait();

    await deployments.execute(
        "VaultRegistry",
        { from: deployer, autoMine: true, ...TRANSACTION_GAS_LIMITS },
        "transferFrom(address,address,uint256)",
        deployer,
        strategyAdmin,
        rootVaultNft
    );
};

export default func;
func.tags = ["SStrategy", ...MAIN_NETWORKS];
func.dependencies = [
    "ProtocolGovernance",
    "VaultRegistry",
    "AllowAllValidator",
    "MellowOracle",
    "ERC20VaultGovernance",
    "ERC20RootVaultGovernanceForCyclic",
    "SqueethVaultGovernance",
    "Finalize"
];
