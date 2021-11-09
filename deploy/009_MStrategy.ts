import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    // const { deployments, getNamedAccounts } = hre;
    // const { deploy, get, log } = deployments;
    // const { deployer, mStrategyTreasury } = await getNamedAccounts();
    // const vaultRegistry = await hre.ethers.getContract("VaultRegistry");
    // if ((await vaultRegistry.vaultsCount()) > 0) {
    //     log("MStrategy already deployed, skipping");
    //     return;
    // }
    // const erc20VaultGovernance = await hre.ethers.getContract(
    //     "ERC20VaultGovernance"
    // );
    // const aaveVaultGovernance = await hre.ethers.getContract(
    //     "AaveVaultGovernance"
    // );
    // const uniV3VaultGovernance = await hre.ethers.getContract(
    //     "UniV3VaultGovernance"
    // );
};
export default func;
func.tags = ["LpIssuerGovernance", "Vaults"];
