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
import { ethers } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read, getOrNull } = deployments;
    const { deployer, admin, protocolTreasury, weth, wbtc, usdc } =
        await getNamedAccounts();
    const tokens = [weth, wbtc, usdc].map((t) => t.toLowerCase()).sort();
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const delay = await read("ProtocolGovernance", "governanceDelay");
    if (delay > 0) {
        log("Protocol governance is already finalized");
        return;
    }
    log("Creating protocol governance finalizing tx");
    const txDatas = [];
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
        const tx =
            await protocolGovernance.populateTransaction.stagePermissionGrants(
                governance.address,
                [PermissionIdsLibrary.REGISTER_VAULT]
            );
        txDatas.push(tx.data);
    }

    for (let token of tokens) {
        const tx =
            await protocolGovernance.populateTransaction.stagePermissionGrants(
                token,
                [
                    PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                    PermissionIdsLibrary.ERC20_TRANSFER,
                ]
            );
        txDatas.push(tx.data);
    }
    if (!ALLOW_ALL_CREATE_VAULT) {
        for (const address of [deployer, admin]) {
            const tx =
                await protocolGovernance.populateTransaction.stagePermissionGrants(
                    address,
                    [PermissionIdsLibrary.CREATE_VAULT]
                );
            txDatas.push(tx.data);
        }
    }
    if (txDatas.length > 0) {
        const tx =
            await protocolGovernance.populateTransaction.commitAllPermissionGrantsSurpassedDelay();
        txDatas.push(tx.data);
    }

    const params = {
        forceAllowMask: ALLOW_MASK,
        maxTokensPerVault: 10,
        governanceDelay: 86400,
        protocolTreasury,
        withdrawLimit: 200000,
    };
    let tx = await protocolGovernance.populateTransaction.setPendingParams(
        params
    );
    txDatas.push(tx.data);
    tx = await protocolGovernance.populateTransaction.commitParams();
    txDatas.push(tx.data);

    const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");
    tx = await protocolGovernance.populateTransaction.grantRole(
        adminRole,
        admin
    );
    txDatas.push(tx.data);
    tx = await protocolGovernance.populateTransaction.renounceRole(
        adminRole,
        deployer
    );
    txDatas.push(tx.data);
    await execute(
        "ProtocolGovernance",
        {
            from: deployer,
            autoMine: true,
        },
        "multicall",
        txDatas
    );
};
export default func;
func.tags = ["Finalize", "core", ...ALL_NETWORKS];
func.dependencies = ["ProtocolGovernance"];
