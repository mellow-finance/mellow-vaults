import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import {
    now,
    randomAddress,
    sleep,
    sleepTo,
    toObject,
} from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import {
    DelayedProtocolParamsStruct,
    DelayedStrategyParamsStruct,
} from "./types/YearnVaultGovernance";
import { BigNumber } from "@ethersproject/bignumber";
import { F } from "ramda";

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

            const { deploy, get } = deployments;
            protocolGovernance = (await get("ProtocolGovernance")).address;
            vaultRegistry = (await get("VaultRegistry")).address;

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

    describe("stageDelayedStrategyParams", () => {
        const paramsToStage: DelayedStrategyParamsStruct = {
            strategyTreasury: randomAddress(),
        };
        let nft: number;
        let deploy: Function;

        before(async () => {
            const { weth, wbtc } = await getNamedAccounts();
            deploy = deployments.createFixture(async () => {
                const tokens = [weth, wbtc].map((t) => t.toLowerCase()).sort();
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: deployer, autoMine: true },
                    "deployVault",
                    tokens,
                    [],
                    deployer
                );
            });
        });

        beforeEach(async () => {
            await deploy();
            nft = (
                await deployments.read("VaultRegistry", "vaultsCount")
            ).toNumber();
        });

        describe("on first call (params are not initialized)", () => {
            beforeEach(async () => {
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: admin, autoMine: true },
                    "stageDelayedStrategyParams",
                    nft,
                    paramsToStage
                );
            });
            it("stages new delayed protocol params", async () => {
                const stagedParams = await deployments.read(
                    "YearnVaultGovernance",
                    "stagedDelayedStrategyParams",
                    nft
                );
                expect(toObject(stagedParams)).to.eql(paramsToStage);
            });

            it("sets the delay = 0 for commit to enable instant init", async () => {
                const timestamp = await deployments.read(
                    "YearnVaultGovernance",
                    "delayedStrategyParamsTimestamp",
                    nft
                );
                expect(timestamp).to.eq(startTimestamp + 3);
            });
        });

        describe("on subsequent calls (params are initialized)", () => {
            beforeEach(async () => {
                const otherParams: DelayedStrategyParamsStruct = {
                    strategyTreasury: randomAddress(),
                };
                // init params
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: admin, autoMine: true },
                    "stageDelayedStrategyParams",
                    nft,
                    otherParams
                );
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: admin, autoMine: true },
                    "commitDelayedStrategyParams",
                    nft
                );
                // call stage again
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: admin, autoMine: true },
                    "stageDelayedStrategyParams",
                    nft,
                    paramsToStage
                );
            });
            it("stages new delayed protocol params", async () => {
                const stagedParams = await deployments.read(
                    "YearnVaultGovernance",
                    "stagedDelayedStrategyParams",
                    nft
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
                    "delayedStrategyParamsTimestamp",
                    nft
                );
                expect(timestamp).to.eq(
                    governanceDelay.add(startTimestamp).add(7)
                );
            });
        });

        describe("when called not by protocol admin", () => {
            it("reverts", async () => {
                for (const actor of [deployer, stranger]) {
                    console.log(
                        "----",
                        nft,
                        (
                            await deployments.read(
                                "VaultRegistry",
                                "vaultsCount"
                            )
                        ).toNumber()
                    );

                    await expect(
                        deployments.execute(
                            "YearnVaultGovernance",
                            { from: actor, autoMine: true },
                            "stageDelayedStrategyParams",
                            nft,
                            paramsToStage
                        )
                    ).to.be.revertedWith(Exceptions.REQUIRE_AT_LEAST_ADMIN);
                }
            });
        });
    });
});
