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
import { now, sleep, sleepTo, toObject, withSigner } from "./library/Helpers";
import { Contract } from "hardhat/internal/hardhat-network/stack-traces/model";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Deployment } from "hardhat-deploy/dist/types";
import { read } from "fs";
import Exceptions from "./library/Exceptions";

describe("YearnVaultGovernance", () => {
    const tokensCount = 2;
    let deploymentFixture: Function;
    let deployer: string;
    let admin: string;
    let stranger: string;
    let yearnVaultRegistry: string;
    let protocolGovernance: string;
    let vaultRegistry: string;

    before(async () => {
        const {
            deployer: d,
            admin: a,
            yearnVaultRegistry: y,
            stranger: s,
        } = await getNamedAccounts();
        [deployer, admin, yearnVaultRegistry, stranger] = [d, a, y, s];

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
            const { read, execute } = deployments;
            await execute(
                "YearnVaultGovernance",
                { from: admin, autoMine: true },
                "stageDelayedProtocolParams",
                params
            );
            const stagedParams = await read(
                "YearnVaultGovernance",
                "stagedDelayedProtocolParams"
            );
            expect(toObject(stagedParams)).to.eql(params);
        });

        it("sets the delay for commit", async () => {
            const { read, execute } = deployments;
            const params = {
                yearnVaultRegistry: vaultRegistry,
            };
            const start = now();

            await sleepTo(start);
            await execute(
                "YearnVaultGovernance",
                { from: admin, autoMine: true },
                "stageDelayedProtocolParams",
                params
            );
            const governanceDelay = await read(
                "ProtocolGovernance",
                "governanceDelay"
            );
            const timestamp = await read(
                "YearnVaultGovernance",
                "delayedProtocolParamsTimestamp"
            );
            expect(timestamp).to.eq(governanceDelay.add(start).add(1));
        });

        describe("when called not by admin", () => {
            it("reverts", async () => {
                const params = {
                    yearnVaultRegistry: vaultRegistry,
                };
                await expect(
                    deployments.execute(
                        "YearnVaultGovernance",
                        { from: deployer, autoMine: true },
                        "stageDelayedProtocolParams",
                        params
                    )
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });
});
