import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { ethers } from "ethers";
import { sendTx } from "./000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute } = deployments;
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const { deployer, protocolTreasury } = await getNamedAccounts();
    const governances = [];
    for (const name of [
        "AaveVaultGovernance",
        "UniV3VaultGovernance",
        "ERC20VaultGovernance",
        "LpIssuerGovernance",
    ]) {
        const governance = await hre.ethers.getContract(name);
        if (await protocolGovernance.isVaultGovernance(governance.address)) {
            continue;
        }
        governances.push(governance.address);
    }
    if (governances.length > 0) {
        log(`Registering Governances in ProtocolGovernance`);
        await execute(
            "ProtocolGovernance",
            { from: deployer, log: true, autoMine: true },
            "setPendingVaultGovernancesAdd",
            governances
        );
        await execute(
            "ProtocolGovernance",
            { from: deployer, log: true, autoMine: true },
            "commitVaultGovernancesAdd"
        );
        log("Done");
    }

    const delay = await protocolGovernance.governanceDelay();
    if (delay == 0) {
        const params = {
            permissionless: true,
            maxTokensPerVault: 10,
            governanceDelay: 86400,
            strategyPerformanceFee: 20 * 10 ** 7,
            protocolPerformanceFee: 3 * 10 ** 7,
            protocolExitFee: 10 ** 7,
            protocolTreasury: protocolTreasury,
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
};
export default func;
func.tags = ["ProtocolGovernance", "Vaults"];
