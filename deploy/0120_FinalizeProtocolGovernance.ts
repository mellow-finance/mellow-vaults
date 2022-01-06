import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { ALL_NETWORKS, AddressPermissionIds } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read, getOrNull } = deployments;
    const { deployer, admin, protocolTreasury, weth, wbtc, usdc } =
        await getNamedAccounts();
    const tokens = [weth, wbtc, usdc].map((t) => t.toLowerCase()).sort();
    const governances = [];
    for (const name of [
        "AaveVaultGovernance",
        "UniV3VaultGovernance",
        "ERC20VaultGovernance",
        "YearnVaultGovernance",
        "ERC20RootVaultGovernance",
    ]) {
        const governance = await getOrNull(name);
        if (!governance) {
            continue;
        }
        if (
            await read(
                "ProtocolGovernance",
                "hasPermission",
                governance.address,
                AddressPermissionIds.VAULT_GOVERNANCE
            )
        ) {
            continue;
        }
        governances.push(governance.address);
    }
    for (let governance of governances) {
        log(`Registering Governances in ProtocolGovernance`);
        await execute(
            "ProtocolGovernance",
            { from: deployer, log: true, autoMine: true },
            "stageGrantPermissions",
            governance,
            AddressPermissionIds.VAULT_GOVERNANCE
        );
        await execute(
            "ProtocolGoverance",
            { from: deployer, log: true, autoMine: true },
            "commitStagedPermissions",
        );
    }

    for (let token of tokens) {
        await execute(
            "ProtocolGovernance",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "stageGrantPermissions",
            token,
            [
                AddressPermissionIds.ERC20_VAULT_TOKEN,
                AddressPermissionIds.ERC20_SWAP,
                AddressPermissionIds.ERC20_TRANSFER
            ]
        );
        await execute(
            "ProtocolGovernance",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "commitStagedPermissions"
        );
    }

    const delay = await read("ProtocolGovernance", "governanceDelay");
    if (delay == 0) {
        const params = {
            permissionless: true,
            maxTokensPerVault: 10,
            governanceDelay: 86400,
            protocolTreasury,
        };
        log(`Setting ProtocolGovernance params`);
        log(JSON.stringify(params, null, 2));
        await execute(
            "ProtocolGovernance",
            { from: deployer, log: true, autoMine: true },
            "setPendingParams",
            params
        );
        await execute(
            "ProtocolGovernance",
            { from: deployer, log: true, autoMine: true },
            "commitParams"
        );
        log("Done");
    }

    const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");
    const deployerIsAdmin = await read(
        "ProtocolGovernance",
        "hasRole",
        adminRole,
        deployer
    );
    if (deployerIsAdmin) {
        await execute(
            "ProtocolGovernance",
            {
                from: deployer,
                autoMine: true,
            },
            "grantRole",
            adminRole,
            admin
        );
        await execute(
            "ProtocolGovernance",
            {
                from: deployer,
                autoMine: true,
            },
            "renounceRole",
            adminRole,
            deployer
        );
    }
};
export default func;
func.tags = ["Finalize", "core", ...ALL_NETWORKS];
func.dependencies = ["ProtocolGovernance"];
