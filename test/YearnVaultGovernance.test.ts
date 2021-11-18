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
import { sleep, toObject, withSigner } from "./library/Helpers";
import { Contract } from "hardhat/internal/hardhat-network/stack-traces/model";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Deployment } from "hardhat-deploy/dist/types";
import { read } from "fs";

describe("YearnVaultGovernance", () => {
    const tokensCount = 2;
    let deploymentFixture: Function;
    let deployer: string;
    let admin: string;
    let yearnVaultRegistry: string;
    let protocolGovernance: string;
    let vaultRegistry: string;

    before(async () => {
        const {
            deployer: d,
            admin: a,
            yearnVaultRegistry: y,
        } = await getNamedAccounts();
        [deployer, admin, yearnVaultRegistry] = [d, a, y];

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();

            const { execute, read, deploy, get } = deployments;
            protocolGovernance = (await get("ProtocolGovernance")).address;
            vaultRegistry = (await get("VaultRegistry")).address;

            const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");

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
            await execute(
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
            await deploy("YearnVaultGovernance", {
                from: deployer,
                args: [
                    {
                        protocolGovernance: protocolGovernance,
                        registry: vaultRegistry,
                    },
                    { yearnVaultRegistry },
                ],
                log: true,
                autoMine: true,
            });
        });
    });

    beforeEach(async () => {
        await deploymentFixture();
    });

    describe("stageDelayedProtocolParams", () => {
        it("stages new delayed protocol params", async () => {
            const params = {
                yearnVaultRegistry: vaultRegistry,
            };
            await deployments.execute(
                "YearnVaultGovernance",
                { from: admin, autoMine: true },
                "stageDelayedProtocolParams",
                params
            );
            const stagedParams = await deployments.read(
                "YearnVaultGovernance",
                "stagedDelayedProtocolParams"
            );
            expect(toObject(stagedParams)).to.eql(params);
        });
    });
});
