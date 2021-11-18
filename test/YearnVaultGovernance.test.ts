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
import {
    now,
    randomAddress,
    sleep,
    sleepTo,
    toObject,
    withSigner,
} from "./library/Helpers";
import { Contract } from "hardhat/internal/hardhat-network/stack-traces/model";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Deployment } from "hardhat-deploy/dist/types";
import { read } from "fs";
import Exceptions from "./library/Exceptions";
import {
    DelayedProtocolParamsStruct,
    DelayedStrategyParamsStruct,
} from "./types/YearnVaultGovernance";

describe("YearnVaultGovernance", () => {
    let deploymentFixture: Function;
    let deployer: string;
    let admin: string;
    let stranger: string;
    let yearnVaultRegistry: string;
    let protocolGovernance: string;
    let vaultRegistry: string;
    let startTimestamp: number;

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
            await deploy("YearnVaultGovernance", {
                from: deployer,
                args: [
                    {
                        protocolGovernance: protocolGovernance,
                        registry: vaultRegistry,
                    },
                    { yearnVaultRegistry },
                ],
                autoMine: true,
            });
        });
    });

    beforeEach(async () => {
        await deploymentFixture();
        startTimestamp = now();
        await sleepTo(startTimestamp);
    });

    describe("stageDelayedProtocolParams", () => {
        const paramsToStage: DelayedProtocolParamsStruct = {
            yearnVaultRegistry: randomAddress(),
        };

        describe("when happy case", () => {
            beforeEach(async () => {
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: admin, autoMine: true },
                    "stageDelayedProtocolParams",
                    paramsToStage
                );
            });
            it("stages new delayed protocol params", async () => {
                const stagedParams = await deployments.read(
                    "YearnVaultGovernance",
                    "stagedDelayedProtocolParams"
                );
                expect(toObject(stagedParams)).to.eql(paramsToStage);
            });

            it("sets the delay for commit", async () => {
                const governanceDelay = await deployments.read(
                    "ProtocolGovernance",
                    "governanceDelay"
                );
                const timestamp = await deployments.read(
                    "YearnVaultGovernance",
                    "delayedProtocolParamsTimestamp"
                );
                expect(timestamp).to.eq(
                    governanceDelay.add(startTimestamp).add(1)
                );
            });
        });

        describe("when called not by protocol admin", () => {
            it("reverts", async () => {
                for (const actor of [deployer, stranger]) {
                    await expect(
                        deployments.execute(
                            "YearnVaultGovernance",
                            { from: actor, autoMine: true },
                            "stageDelayedProtocolParams",
                            paramsToStage
                        )
                    ).to.be.revertedWith(Exceptions.ADMIN);
                }
            });
        });
    });

    describe("commitDelayedProtocolParams", () => {
        const paramsToCommit: DelayedProtocolParamsStruct = {
            yearnVaultRegistry: randomAddress(),
        };

        describe("when happy case", () => {
            beforeEach(async () => {
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: admin, autoMine: true },
                    "stageDelayedProtocolParams",
                    paramsToCommit
                );
                const governanceDelay = await deployments.read(
                    "ProtocolGovernance",
                    "governanceDelay"
                );
                await sleep(governanceDelay);
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: admin, autoMine: true },
                    "commitDelayedProtocolParams"
                );
            });
            it("commits staged protocol params", async () => {
                const protocolParams = await deployments.read(
                    "YearnVaultGovernance",
                    "delayedProtocolParams"
                );
                expect(toObject(protocolParams)).to.eql(paramsToCommit);
            });
            it("resets staged protocol params", async () => {
                const stagedProtocolParams = await deployments.read(
                    "YearnVaultGovernance",
                    "stagedDelayedProtocolParams"
                );
                expect(toObject(stagedProtocolParams)).to.eql({
                    yearnVaultRegistry: ethers.constants.AddressZero,
                });
            });
            it("resets staged protocol params timestamp", async () => {
                const stagedProtocolParams = await deployments.read(
                    "YearnVaultGovernance",
                    "delayedProtocolParamsTimestamp"
                );
                expect(toObject(stagedProtocolParams)).to.eq(0);
            });
        });

        describe("when called not by admin", () => {
            it("reverts", async () => {
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: admin, autoMine: true },
                    "stageDelayedProtocolParams",
                    paramsToCommit
                );
                const governanceDelay = await deployments.read(
                    "ProtocolGovernance",
                    "governanceDelay"
                );
                await sleep(governanceDelay);

                for (const actor of [deployer, stranger]) {
                    await expect(
                        deployments.execute(
                            "YearnVaultGovernance",
                            { from: actor, autoMine: true },
                            "stageDelayedProtocolParams",
                            paramsToCommit
                        )
                    ).to.be.revertedWith(Exceptions.ADMIN);
                }
            });
        });

        describe("when time before delay has not elapsed", () => {
            it("reverts", async () => {
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: admin, autoMine: true },
                    "stageDelayedProtocolParams",
                    paramsToCommit
                );
                // immediate execution
                await expect(
                    deployments.execute(
                        "YearnVaultGovernance",
                        { from: admin, autoMine: true },
                        "commitDelayedProtocolParams"
                    )
                ).to.be.revertedWith(Exceptions.TIMESTAMP);

                const governanceDelay = await deployments.read(
                    "ProtocolGovernance",
                    "governanceDelay"
                );
                await sleep(governanceDelay.sub(15));
                // execution one second before the deadline
                await expect(
                    deployments.execute(
                        "YearnVaultGovernance",
                        { from: admin, autoMine: true },
                        "commitDelayedProtocolParams"
                    )
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });
    });
});
