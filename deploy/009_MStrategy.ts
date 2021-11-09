import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { sendTx } from "./000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute } = deployments;
    const { deployer, mStrategyTreasury, weth, usdc } =
        await getNamedAccounts();
    const vaultRegistry = await hre.ethers.getContract("VaultRegistry");
    const erc20VaultGovernance = await hre.ethers.getContract(
        "ERC20VaultGovernance"
    );
    const aaveVaultGovernance = await hre.ethers.getContract(
        "AaveVaultGovernance"
    );
    const uniV3VaultGovernance = await hre.ethers.getContract(
        "UniV3VaultGovernance"
    );
    const gatewayVaultGovernance = await hre.ethers.getContract(
        "GatewayVaultGovernance"
    );
    const lpIssuerVaultGovernance = await hre.ethers.getContract(
        "LpIssuerGovernance"
    );

    const tokens = [weth, usdc].sort();
    let startNft = (await vaultRegistry.vaultsCount()) + 1;
    const coder = hre.ethers.utils.defaultAbiCoder;
    let aaveVaultNft = 1;
    let uniV3VaultNft = 2;
    let erc20VaultNft = 3;
    let gatewayVaultNft = 4;
    let lpIssuerNft = 5;
    if (startNft <= aaveVaultNft) {
        log("Deploying Aave vault...");
        await execute(
            "AaveVaultGovernance",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "deployVault",
            tokens,
            [],
            deployer
        );
        log(`Done, nft = ${aaveVaultNft}`);
    } else {
        log(`Aave vault with nft = ${aaveVaultNft} already deployed`);
    }
    if (startNft <= uniV3VaultNft) {
        log("Deploying UniV3 vault...");

        await execute(
            "UniV3VaultGovernance",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "deployVault",
            tokens,
            coder.encode(["uint256"], [3000]),
            deployer
        );
        log(`Done, nft = ${uniV3VaultNft}`);
    } else {
        log(`UniV3 vault with nft = ${uniV3VaultNft} already deployed`);
    }
    if (startNft <= erc20VaultNft) {
        log("Deploying ERC20 vault...");
        await execute(
            "ERC20VaultGovernance",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "deployVault",
            tokens,
            [],
            deployer
        );
        log(`Done, nft = ${erc20VaultNft}`);
    } else {
        log(`ERC20 vault with nft = ${erc20VaultNft} already deployed`);
    }
    const approvedGw = await vaultRegistry.isApprovedForAll(
        deployer,
        gatewayVaultGovernance.address
    );
    const approvedIssuer = await vaultRegistry.isApprovedForAll(
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
    if (startNft <= gatewayVaultNft) {
        log("Deploying GatewayVault");
        await execute(
            "GatewayVaultGovernance",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "deployVault",
            tokens,
            coder.encode(
                ["uint256[]"],
                [[uniV3VaultNft, aaveVaultNft, erc20VaultNft]]
            ),
            deployer
        );
        log(`Done, nft = ${gatewayVaultNft}`);
    } else {
        log(`Gateway vault with nft = ${gatewayVaultNft} already deployed`);
    }
    if (startNft <= lpIssuerNft) {
        log("Deploying LpIssuer vault...");
        await execute(
            "LpIssuerGovernance",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "deployVault",
            tokens,
            coder.encode(
                ["uint256", "string", "string"],
                [gatewayVaultNft, "MStrategy LP Token", "MSLP"]
            ),
            deployer
        );
        log(`Done, nft = ${lpIssuerNft}`);
    } else {
        log(`Lp Issuer with nft = ${lpIssuerNft} already deployed`);
    }
};
export default func;
func.tags = ["MStrategy"];
