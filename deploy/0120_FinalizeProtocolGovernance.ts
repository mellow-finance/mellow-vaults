import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {
    ALLOW_ALL_CREATE_VAULT,
    ALLOW_MASK,
    ALL_NETWORKS,
    PermissionIdsLibrary,
    PRIVATE_VAULT,
} from "./0000_utils";

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
                PermissionIdsLibrary.REGISTER_VAULT
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
            [PermissionIdsLibrary.REGISTER_VAULT]
        );
        // await new Promise((resolve) => setTimeout(resolve, 10000));
    }
    if (governances.length > 0) {
        await execute(
            "ProtocolGovernance",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "commitStagedPermissions"
        );
        // await new Promise((resolve) => setTimeout(resolve, 10000));
    }

    for (let token of tokens) {
        if (
            await read(
                "ProtocolGovernance",
                "hasPermission",
                token,
                PermissionIdsLibrary.ERC20_VAULT_TOKEN
            )
        ) {
            continue;
        }

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
                PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                PermissionIdsLibrary.ERC20_SWAP,
                PermissionIdsLibrary.ERC20_TRANSFER,
            ]
        );
        // await new Promise((resolve) => setTimeout(resolve, 10000));
    }
    if (!ALLOW_ALL_CREATE_VAULT) {
        for (const address of [deployer, admin]) {
            if (
                await read(
                    "ProtocolGovernance",
                    "hasPermission",
                    address,
                    PermissionIdsLibrary.CREATE_VAULT
                )
            ) {
                continue;
            }

            await execute(
                "ProtocolGovernance",
                { from: deployer, log: true, autoMine: true },
                "stageGrantPermissions",
                address,
                [PermissionIdsLibrary.CREATE_VAULT]
            );
            // await new Promise((resolve) => setTimeout(resolve, 10000));
        }
    }
    const staged = await read(
        "ProtocolGovernance",
        "stagedPermissionAddresses"
    );

    if (staged.length > 0) {
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
            forceAllowMask: ALLOW_MASK,
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
