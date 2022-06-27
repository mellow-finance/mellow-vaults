import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {ALL_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";
import {BigNumber} from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { address: oracle } = await get("MellowOracle");
    const { deployer, aaveLendingPool } = await getNamedAccounts();
    const { address: singleton } = await deploy("ERC20RootVault", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
    const { address: helperAddress } = await deploy(
        "ERC20RootVaultHelper",
        {
            from: deployer,
            args: [],
            log: true,
            autoMine: true,
            ...TRANSACTION_GAS_LIMITS
        }
    );
    const { address: ERC20RootVaultGovernanceAddress } = await deploy(
        "ERC20RootVaultGovernance",
        {
            from: deployer,
            args: [
                {
                    protocolGovernance: protocolGovernance.address,
                    registry: vaultRegistry.address,
                    singleton,
                },
                { managementFeeChargeDelay: 86400, oracle},
                helperAddress
            ],
            log: true,
            autoMine: true,
            ...TRANSACTION_GAS_LIMITS
        }
    );
    const approvedIssuer = await read(
        "VaultRegistry",
        "isApprovedForAll",
        deployer,
        ERC20RootVaultGovernanceAddress
    );
    if (!approvedIssuer) {
        log("Approving ERC20RootVault governance");
        await execute(
            "VaultRegistry",
            {
                from: deployer,
                log: true,
                autoMine: true,
                ...TRANSACTION_GAS_LIMITS
            },
            "setApprovalForAll",
            ERC20RootVaultGovernanceAddress,
            true
        );
    }
};
export default func;
func.tags = ["ERC20RootVaultGovernance", "core", ...ALL_NETWORKS];
func.dependencies = ["ProtocolGovernance", "VaultRegistry", "MellowOracle"];
