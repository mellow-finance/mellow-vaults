import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { Signer } from "ethers";
import {
    ERC20,
    Vault,
    VaultGovernance,
    ProtocolGovernance,
} from "./library/Types";
import { deploySubVaultSystem } from "./library/Deployments";
import { sleep } from "./library/Helpers";
import { Contract } from "hardhat/internal/hardhat-network/stack-traces/model";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";

describe("YearnVaultGovernance", () => {
    const tokensCount = 2;
    let deploymentFixture: Function;
    let deployer: string;
    let admin: string;

    before(async () => {
        const { deployer: d, admin: a } = await getNamedAccounts();
        [deployer, admin] = [d, a];

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            const { execute, read } = deployments;
            const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");
            console.log(adminRole, deployer, admin);

            await execute(
                "ProtocolGovernance",
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                },
                "grantRole",
                adminRole,
                admin
            );
            await await execute(
                "ProtocolGovernance",
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                },
                "renounceRole",
                adminRole,
                deployer
            );
        });
    });

    beforeEach(async () => {
        await deploymentFixture();
    });

    it("succeeds", async () => {});
});
