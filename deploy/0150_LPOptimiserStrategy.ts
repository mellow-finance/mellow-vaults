import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {
    combineVaults,
    MAIN_NETWORKS,
    setupVault,
} from "./0000_utils";
import { BigNumber } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, read, log } = deployments;
    const {
        deployer,
        usdc,
        marginEngine,
        mStrategyTreasury,
        mStrategyAdmin,
    } = await getNamedAccounts();

    const tokens = [usdc].map((t) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let voltzVaultNft = startNft;
    let erc20VaultNft = startNft + 1;

    const voltzVaultHelper = (await ethers.getContract("VoltzVaultHelper")).address;

    await setupVault(hre, voltzVaultNft, "VoltzVaultGovernance", {
        createVaultArgs: [tokens, deployer, marginEngine, voltzVaultHelper, {
            tickLower: 0,
            tickUpper: 60,
            leverageWad: BigNumber.from("10000000000000000000"), // 10
            marginMultiplierPostUnwindWad: BigNumber.from("2000000000000000000"), // 2
            lookbackWindowInSeconds: 1209600, // 14 days
            estimatedAPYDecimalDeltaWad: BigNumber.from("0")
        }],
    });
    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );
    const voltzVault = await read(
        "VaultRegistry",
        "vaultForNft",
        voltzVaultNft
    );

    let strategyDeployParams = await deploy("LPOptimiserStrategy", {
        from: deployer,
        contract: "LPOptimiserStrategy",
        args: [
            erc20Vault,
            [voltzVault],
            [{
                sigmaWad: "100000000000000000",
                maxPossibleLowerBoundWad: "1500000000000000000",
                proximityWad: "100000000000000000",
                weight: "1"
            }],
            deployer,
        ],
        log: true,
        autoMine: true,
    });

    await combineVaults(
        hre,
        erc20VaultNft + 1,
        [erc20VaultNft, voltzVaultNft],
        strategyDeployParams.address,
        mStrategyTreasury
    );

    const lPOptimiserStrategy = await ethers.getContract("LPOptimiserStrategy");

    log("Transferring ownership to LPOptimiserStrategy");

    const ADMIN_ROLE =
        "0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8"; // keccak256("admin")
    const ADMIN_DELEGATE_ROLE =
        "0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7"; // keccak256("admin_delegate")
    const OPERATOR_ROLE =
        "0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622"; // keccak256("operator")

    await lPOptimiserStrategy.grantRole(ADMIN_ROLE, mStrategyAdmin);
    await lPOptimiserStrategy.grantRole(ADMIN_DELEGATE_ROLE, mStrategyAdmin);
    await lPOptimiserStrategy.grantRole(ADMIN_DELEGATE_ROLE, deployer);
    await lPOptimiserStrategy.grantRole(OPERATOR_ROLE, mStrategyAdmin);
    await lPOptimiserStrategy.revokeRole(OPERATOR_ROLE, deployer);
    await lPOptimiserStrategy.revokeRole(ADMIN_DELEGATE_ROLE, deployer);
    await lPOptimiserStrategy.revokeRole(ADMIN_ROLE, deployer);
};

export default func;
func.tags = ["LPOptimiserStrategy", ...MAIN_NETWORKS];
func.dependencies = [
    "ProtocolGovernance",
    "VaultRegistry",
    "VoltzVaultGovernance",
    "ERC20VaultGovernance",
];
