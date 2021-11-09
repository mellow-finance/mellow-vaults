import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { log } = deployments;
    const { deployer, mStrategyTreasury, weth, usdc } =
        await getNamedAccounts();
    const vaultRegistry = await hre.ethers.getContract("VaultRegistry");
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
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
    if (startNft >= 6) {
        log("M strategy already deployed");
        return;
    }
    log("Deploying Aave vault...");
    await aaveVaultGovernance.deployVault(tokens, [], deployer);
    const aaveVaultNft = startNft;
    log(`Done, nft = ${aaveVaultNft}`);
    startNft++;
    log("Deploying UniV3 vault...");
    const coder = hre.ethers.utils.defaultAbiCoder;
    await uniV3VaultGovernance.deployVault(
        tokens,
        coder.encode(["uint256"], [3000]),
        deployer
    );
    const uniV3VaultNft = startNft;
    log(`Done, nft = ${uniV3VaultNft}`);
    startNft++;
    log("Deploying ERC20 vault...");
    await erc20VaultGovernance.deployVault(tokens, [], deployer);
    const erc20VaultNft = startNft;
    log(`Done, nft = ${erc20VaultNft}`);
    startNft++;
    log("Approving gateway and lp issuer vault governance");
    await vaultRegistry.setApprovalForAll(gatewayVaultGovernance.address, true);
    await vaultRegistry.setApprovalForAll(
        lpIssuerVaultGovernance.address,
        true
    );
    log("Done");
    log("Deploying GatewayVault");
    await uniV3VaultGovernance.deployVault(
        tokens,
        coder.encode(
            ["uint256[]"],
            [[uniV3VaultNft, aaveVaultNft, erc20VaultNft]]
        ),
        deployer
    );
    const gatewayVaultNft = startNft;
    log(`Done, nft = ${gatewayVaultNft}`);
    startNft++;
    log("Deploying UniV3 vault...");
    await uniV3VaultGovernance.deployVault(
        tokens,
        coder.encode(["uint256"], [gatewayVaultNft]),
        deployer
    );
    const lpIssuerNft = startNft;
    log(`Done, nft = ${lpIssuerNft}`);
    startNft++;
};
export default func;
func.tags = ["LpIssuerGovernance", "Vaults"];
