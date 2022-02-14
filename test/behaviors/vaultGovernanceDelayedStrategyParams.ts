import { BigNumber, Contract, ethers, Signer } from "ethers";
import { Arbitrary, nat, Random } from "fast-check";
import { type } from "os";
import {
    generateParams,
    now,
    randomAddress,
    sleep,
    sleepTo,
    toObject,
    withSigner,
    zeroify,
} from "../library/Helpers";
import { address, pit, RUNS } from "../library/property";
import { equals } from "ramda";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import Exceptions from "../library/Exceptions";
import { VaultGovernanceContext } from "./vaultGovernance";
import { deployments } from "hardhat";

export function delayedStrategyParamsBehavior<P, S extends Contract, F>(
    this: VaultGovernanceContext<S, F>,
    paramsArb: Arbitrary<P>
) {
    let someParams: P;
    let noneParams: P;
    this.beforeEach(() => {
        ({ someParams, noneParams } = generateParams(paramsArb));
    });

    describe(`#stagedDelayedStrategyParams`, () => {
        it(`returns DelayedStrategyParams staged for commit`, async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedStrategyParams(this.nft, someParams);
            const actualParams = await this.subject.stagedDelayedStrategyParams(
                this.nft
            );
            expect(someParams).to.be.equivalent(actualParams);
        });

        describe("properties", () => {
            pit(
                "always equals to params that were just staged",
                { numRuns: RUNS.low },
                paramsArb,
                async (params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, params);
                    const actualParams =
                        await this.subject.stagedDelayedStrategyParams(
                            this.nft
                        );

                    return equals(toObject(actualParams), params);
                }
            );
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .stagedDelayedStrategyParams(this.nft)
                    ).to.not.be.reverted;
                });
            });
        });
        describe("edge cases", () => {
            describe("when no params are staged for commit", () => {
                it("returns zero struct", async () => {
                    const actualParams =
                        await this.subject.stagedDelayedStrategyParams(
                            this.nft
                        );
                    expect(noneParams).to.equivalent(actualParams);
                });
            });

            describe("when params were just committed", () => {
                it("returns zero struct", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someParams);
                    await sleep(this.governanceDelay);
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedStrategyParams(this.nft);
                    const actualParams =
                        await this.subject.stagedDelayedStrategyParams(
                            this.nft
                        );
                    expect(noneParams).to.equivalent(actualParams);
                });
            });
        });
    });

    describe(`#delayedStrategyParams`, () => {
        it(`returns current DelayedStrategyParams`, async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedStrategyParams(this.nft, someParams);
            await sleep(this.governanceDelay);
            await this.subject
                .connect(this.admin)
                .commitDelayedStrategyParams(this.nft);
            const actualParams = await this.subject.delayedStrategyParams(
                this.nft
            );
            expect(someParams).to.equivalent(actualParams);
        });
        describe("properties", () => {
            pit(
                `staging DelayedStrategyParams doesn't change delayedStrategyParams`,
                { numRuns: RUNS.low },
                paramsArb,
                async (params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, params);
                    const actualParams =
                        await this.subject.delayedStrategyParams(this.nft);

                    return !equals(toObject(actualParams), params);
                }
            );
        });
        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).delayedStrategyParams(this.nft)
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when no params were committed", () => {
                it("returns zero params", async () => {
                    const actualParams =
                        await this.subject.delayedStrategyParams(this.nft);
                    expect(actualParams).to.be.equivalent(noneParams);
                });
            });
        });
    });

    describe("#stageDelayedStrategyParams", () => {
        it("stages DelayedStrategyParams for commit", async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedStrategyParams(this.nft, someParams);
            const actualParams = await this.subject.stagedDelayedStrategyParams(
                this.nft
            );
            expect(someParams).to.be.equivalent(actualParams);
        });
        it("sets zero delay for commit when #commitDelayedStrategyParams was called 0 times (init)", async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedStrategyParams(this.nft, someParams);
            expect(
                await this.subject.delayedStrategyParamsTimestamp(this.nft)
            ).to.be.within(this.startTimestamp, this.startTimestamp + 60);
        });
        it("sets governance delay for commit after #commitDelayedStrategyParams was called at least once", async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedStrategyParams(this.nft, someParams);
            await this.subject
                .connect(this.admin)
                .commitDelayedStrategyParams(this.nft);

            await this.subject
                .connect(this.admin)
                .stageDelayedStrategyParams(this.nft, someParams);
            expect(
                await this.subject.delayedStrategyParamsTimestamp(this.nft)
            ).to.be.within(
                this.governanceDelay + this.startTimestamp,
                this.governanceDelay + this.startTimestamp + 60
            );
        });
        it("emits StageDelayedStrategyParams event", async () => {
            await expect(
                this.subject
                    .connect(this.admin)
                    .stageDelayedStrategyParams(this.nft, someParams)
            ).to.emit(this.subject, "StageDelayedStrategyParams");
        });

        describe("properties", () => {
            pit(
                "cannot be called by random address",
                { numRuns: RUNS.verylow },
                address,
                paramsArb,
                async (addr: string, params: P) => {
                    await withSigner(addr, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .stageDelayedStrategyParams(this.nft, params)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                }
            );
        });

        describe("access control", () => {
            it("allowed: ProtocolGovernance admin", async () => {
                await this.subject
                    .connect(this.admin)
                    .stageDelayedStrategyParams(this.nft, someParams);
            });
            it("allowed: Vault NFT Approved (aka strategy)", async () => {
                await expect(
                    this.subject
                        .connect(this.strategySigner)
                        .stageDelayedStrategyParams(this.nft, someParams)
                ).to.not.be.reverted;
            });

            it("allowed: Vault NFT Owner (aka liquidity provider)", async () => {
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .stageDelayedStrategyParams(this.nft, someParams)
                ).to.not.be.reverted;
            });
            it("denied: deployer", async () => {
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .stageDelayedStrategyParams(this.nft, someParams)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });

            it("denied: random address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .stageDelayedStrategyParams(this.nft, someParams)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });

        describe("edge cases", () => {
            describe("when called twice", () => {
                it("succeeds with the last value", async () => {
                    const { someParams: someOtherParams } =
                        generateParams(paramsArb);
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someParams);
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someOtherParams);
                    const actualParams =
                        await this.subject.stagedDelayedStrategyParams(
                            this.nft
                        );
                    expect(someOtherParams).to.be.equivalent(actualParams);
                });
            });
            describe("when called with zero params", () => {
                it("succeeds with zero params", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, noneParams);
                    const actualParams =
                        await this.subject.stagedDelayedStrategyParams(
                            this.nft
                        );
                    expect(noneParams).to.be.equivalent(actualParams);
                });
            });
        });
    });

    describe("#commitDelayedStrategyParams", () => {
        let stagedFixture: Function;
        before(async () => {
            stagedFixture = await deployments.createFixture(async () => {
                await this.deploymentFixture();
                await this.subject
                    .connect(this.admin)
                    .stageDelayedStrategyParams(this.nft, someParams);
            });
        });
        beforeEach(async () => {
            await stagedFixture();
            await sleep(this.governanceDelay);
        });
        it("commits staged DelayedStrategyParams", async () => {
            await this.subject
                .connect(this.admin)
                .commitDelayedStrategyParams(this.nft);

            const actualParams = await this.subject.delayedStrategyParams(
                this.nft
            );
            expect(someParams).to.be.equivalent(actualParams);
        });
        it("resets delay for commit", async () => {
            await this.subject
                .connect(this.admin)
                .commitDelayedStrategyParams(this.nft);
            expect(
                await this.subject.delayedStrategyParamsTimestamp(this.nft)
            ).to.equal(BigNumber.from(0));
        });
        it("emits CommitDelayedStrategyParams event", async () => {
            await expect(
                await this.subject
                    .connect(this.admin)
                    .commitDelayedStrategyParams(this.nft)
            ).to.emit(this.subject, "CommitDelayedStrategyParams");
        });

        describe("properties", () => {
            pit(
                "cannot be called by random address",
                { numRuns: RUNS.verylow },
                address,
                paramsArb,
                async (addr: string, params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someParams);
                    await sleep(this.governanceDelay);

                    await withSigner(addr, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .commitDelayedStrategyParams(this.nft)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                }
            );
            pit(
                "reverts if called before the delay has elapsed (after commit was called initally)",
                { numRuns: RUNS.mid },
                async () => nat((await this.governanceDelay) - 60),
                paramsArb,
                async (delay: number, params: P) => {
                    // Fire off initial commit
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someParams);
                    await sleep(this.governanceDelay);
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedStrategyParams(this.nft);

                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someParams);
                    await sleep(delay);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedStrategyParams(this.nft)
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    return true;
                }
            );
            pit(
                "succeeds if called after the delay has elapsed",
                { numRuns: RUNS.mid },
                nat(),
                paramsArb,
                async (delay: number, params: P) => {
                    // Fire off initial commit
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someParams);
                    await sleep(this.governanceDelay);
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedStrategyParams(this.nft);

                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someParams);
                    await sleep(this.governanceDelay + 60 + delay);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedStrategyParams(this.nft)
                    ).to.not.be.reverted;
                    return true;
                }
            );
        });

        describe("access control", () => {
            it("allowed: ProtocolGovernance admin", async () => {
                await this.subject
                    .connect(this.admin)
                    .commitDelayedStrategyParams(this.nft);
            });

            it("allowed: Vault NFT Owner (aka liquidity provider)", async () => {
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .commitDelayedStrategyParams(this.nft)
                ).to.not.be.reverted;
            });
            it("allowed: Vault NFT Approved (aka strategy)", async () => {
                await expect(
                    this.subject
                        .connect(this.strategySigner)
                        .commitDelayedStrategyParams(this.nft)
                ).to.not.be.reverted;
            });
            it("denied: deployer", async () => {
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .commitDelayedStrategyParams(this.nft)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });

            it("denied: random address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .commitDelayedStrategyParams(this.nft)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });

        describe("edge cases", () => {
            describe("when called twice", () => {
                it("reverts", async () => {
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedStrategyParams(this.nft);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedStrategyParams(this.nft)
                    ).to.be.revertedWith(Exceptions.NULL);
                });
            });
            describe("when nothing is staged", () => {
                it("reverts", async () => {
                    await this.deploymentFixture();
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedStrategyParams(this.nft)
                    ).to.be.revertedWith(Exceptions.NULL);
                });
            });
            describe("when delay has not elapsed (after initial commit call)", () => {
                it("reverts", async () => {
                    await this.deploymentFixture();
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someParams);
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedStrategyParams(this.nft);

                    await this.subject
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.nft, someParams);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedStrategyParams(this.nft)
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    await sleep(this.governanceDelay - 60);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedStrategyParams(this.nft)
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    await sleep(60);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedStrategyParams(this.nft)
                    ).to.not.be.reverted;
                });
            });
        });
    });
}
