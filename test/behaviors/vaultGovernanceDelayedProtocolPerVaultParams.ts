import { BigNumber, Contract, ethers, Signer } from "ethers";
import { Arbitrary, integer, nat } from "fast-check";
import {
    generateParams,
    now,
    randomAddress,
    randomNft,
    sleep,
    sleepTo,
    toObject,
    withSigner,
} from "../library/Helpers";
import { address, pit, RUNS } from "../library/property";
import { equals } from "ramda";
import { expect } from "chai";
import Exceptions from "../library/Exceptions";
import { VaultGovernanceContext } from "./vaultGovernance";
import { deployments } from "hardhat";

export function delayedProtocolPerVaultParamsBehavior<P, S extends Contract, F>(
    this: VaultGovernanceContext<S, F>,
    paramsArb: Arbitrary<P>
) {
    let someParams: P;
    let noneParams: P;
    let nft: Number;
    this.beforeEach(() => {
        ({ someParams, noneParams } = generateParams(paramsArb));
        nft = randomNft();
    });

    describe(`#stagedDelayedProtocolPerVaultParams`, () => {
        it(`returns DelayedProtocolPerVaultParams staged for commit`, async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolPerVaultParams(nft, someParams);
            const actualParams =
                await this.subject.stagedDelayedProtocolPerVaultParams(nft);
            expect(someParams).to.be.equivalent(actualParams);
        });

        describe("properties", () => {
            pit(
                "always equals to params that were just staged",
                { numRuns: RUNS.low },
                paramsArb,
                integer({ min: 0, max: 10 ** 9 }),
                async (params: P, nft: Number) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, params);
                    const actualParams =
                        await this.subject.stagedDelayedProtocolPerVaultParams(
                            nft
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
                            .stagedDelayedProtocolPerVaultParams(randomNft())
                    ).to.not.be.reverted;
                });
            });
        });
        describe("edge cases", () => {
            describe("when no params are staged for commit", () => {
                it("returns zero struct", async () => {
                    const actualParams =
                        await this.subject.stagedDelayedProtocolPerVaultParams(
                            randomNft()
                        );
                    expect(noneParams).to.equivalent(actualParams);
                });
            });

            describe("when params were just committed", () => {
                it("returns zero struct", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, someParams);
                    await sleep(this.governanceDelay);
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedProtocolPerVaultParams(nft);
                    const actualParams =
                        await this.subject.stagedDelayedProtocolPerVaultParams(
                            nft
                        );
                    expect(noneParams).to.equivalent(actualParams);
                });
            });
        });
    });

    describe(`#delayedProtocolPerVaultParams`, () => {
        it(`returns current DelayedProtocolPerVaultParams`, async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolPerVaultParams(nft, someParams);
            await sleep(this.governanceDelay);
            await this.subject
                .connect(this.admin)
                .commitDelayedProtocolPerVaultParams(nft);
            const actualParams =
                await this.subject.delayedProtocolPerVaultParams(nft);
            expect(someParams).to.equivalent(actualParams);
        });
        describe("properties", () => {
            pit(
                `staging DelayedProtocolPerVaultParams doesn't change delayedProtocolPerVaultParams`,
                { numRuns: RUNS.low },
                paramsArb,
                integer({ min: 0, max: 10 ** 9 }),
                async (params: P, nft: Number) => {
                    //stage and commit some non-zero params
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, someParams);
                    await sleep(this.governanceDelay);
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedProtocolPerVaultParams(nft);

                    // after staging some other params delayedProtocolPerVaultParams remain constant
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, params);
                    const actualParams =
                        await this.subject.delayedProtocolPerVaultParams(nft);

                    return !equals(toObject(actualParams), params);
                }
            );
        });
        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .delayedProtocolPerVaultParams(nft)
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when no params were committed", () => {
                it("returns zero params", async () => {
                    const actualParams =
                        await this.subject.delayedProtocolPerVaultParams(nft);
                    expect(actualParams).to.be.equivalent(noneParams);
                });
            });
        });
    });

    describe("#stageDelayedProtocolPerVaultParams", () => {
        it("stages DelayedProtocolPerVaultParams for commit", async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolPerVaultParams(nft, someParams);
            const actualParams =
                await this.subject.stagedDelayedProtocolPerVaultParams(nft);
            expect(someParams).to.be.equivalent(actualParams);
        });

        it("sets delay for commit", async () => {
            let timestamp = now() + 10 ** 6;
            await sleepTo(timestamp);
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolPerVaultParams(nft, someParams);
            expect(
                await this.subject.delayedProtocolPerVaultParamsTimestamp(nft)
            ).to.be.within(timestamp, timestamp + 10);
        });

        it("emits StageDelayedProtocolPerVaultParams event", async () => {
            await expect(
                this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolPerVaultParams(nft, someParams)
            ).to.emit(this.subject, "StageDelayedProtocolPerVaultParams");
        });

        describe("properties", () => {
            pit(
                "cannot be called by random address",
                { numRuns: RUNS.verylow },
                address,
                paramsArb,
                integer({ min: 0, max: 10 ** 9 }),
                async (addr: string, params: P, nft) => {
                    await withSigner(addr, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .stageDelayedProtocolPerVaultParams(nft, params)
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
                    .stageDelayedProtocolPerVaultParams(nft, someParams);
            });

            it("denied: Vault NFT Owner (aka liquidity provider)", async () => {
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .stageDelayedProtocolPerVaultParams(nft, someParams)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
            it("denied: Vault NFT Approved (aka strategy)", async () => {
                await expect(
                    this.subject
                        .connect(this.strategySigner)
                        .stageDelayedProtocolPerVaultParams(nft, someParams)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
            it("denied: deployer", async () => {
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .stageDelayedProtocolPerVaultParams(nft, someParams)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });

            it("denied: random address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .stageDelayedProtocolPerVaultParams(nft, someParams)
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
                        .stageDelayedProtocolPerVaultParams(nft, someParams);
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(
                            nft,
                            someOtherParams
                        );
                    const actualParams =
                        await this.subject.stagedDelayedProtocolPerVaultParams(
                            nft
                        );
                    expect(someOtherParams).to.be.equivalent(actualParams);
                });
            });
            describe("when called with zero params", () => {
                it("succeeds with zero params", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, noneParams);
                    const actualParams =
                        await this.subject.stagedDelayedProtocolPerVaultParams(
                            nft
                        );
                    expect(noneParams).to.be.equivalent(actualParams);
                });
            });
            describe("when protocol fee is greater than MAX_PROTOCOL_FEE", () => {
                it("reverts", async () => {
                    let paramsInvalid = {
                        protocolFee: (
                            await this.subject.MAX_PROTOCOL_FEE()
                        ).add(1),
                    };
                    await expect(
                        this.subject.stageDelayedProtocolPerVaultParams(
                            nft,
                            paramsInvalid
                        )
                    ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                });
            });
        });
    });

    describe("#commitDelayedProtocolPerVaultParams", () => {
        let stagedFixture: Function;
        before(async () => {
            stagedFixture = await deployments.createFixture(async () => {
                await this.deploymentFixture();
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolPerVaultParams(nft, someParams);
            });
        });
        beforeEach(async () => {
            await stagedFixture();
            await sleep(this.governanceDelay);
        });
        it("commits staged DelayedProtocolPerVaultParams", async () => {
            await this.subject
                .connect(this.admin)
                .commitDelayedProtocolPerVaultParams(nft);

            const actualParams =
                await this.subject.delayedProtocolPerVaultParams(nft);
            expect(someParams).to.be.equivalent(actualParams);
        });
        it("resets delay for commit", async () => {
            await this.subject
                .connect(this.admin)
                .commitDelayedProtocolPerVaultParams(nft);
            expect(
                await this.subject.delayedProtocolPerVaultParamsTimestamp(nft)
            ).to.equal(BigNumber.from(0));
        });
        it("emits CommitDelayedProtocolPerVaultParams event", async () => {
            await expect(
                await this.subject
                    .connect(this.admin)
                    .commitDelayedProtocolPerVaultParams(nft)
            ).to.emit(this.subject, "CommitDelayedProtocolPerVaultParams");
        });

        describe("properties", () => {
            pit(
                "cannot be called by random address",
                { numRuns: RUNS.verylow },
                address,
                paramsArb,
                integer({ min: 0, max: 10 ** 9 }),
                async (addr: string, params: P, nft) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, params);
                    await sleep(this.governanceDelay);

                    await withSigner(addr, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .commitDelayedProtocolPerVaultParams(nft)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                }
            );
            pit(
                "reverts if called before the delay has elapsed only if params have already been commited",
                { numRuns: RUNS.mid, endOnFailure: true },
                async () => nat(this.governanceDelay - 60),
                paramsArb,
                integer({ min: 0, max: 10 ** 9 }),
                async (delay: number, params: P, nft) => {
                    await this.deploymentFixture();
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, someParams);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.not.be.revertedWith(Exceptions.TIMESTAMP);

                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, params);
                    await sleep(delay);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    return true;
                }
            );
            pit(
                "succeeds if called after the delay has elapsed",
                { numRuns: RUNS.mid },
                nat(),
                paramsArb,
                integer({ min: 0, max: 10 ** 9 }),
                async (delay: number, params: P, nft) => {
                    await this.deploymentFixture();
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, params);
                    await sleep(this.governanceDelay + 60 + delay);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.not.be.reverted;
                    return true;
                }
            );
        });

        describe("access control", () => {
            it("allowed: ProtocolGovernance admin", async () => {
                await this.subject
                    .connect(this.admin)
                    .commitDelayedProtocolPerVaultParams(nft);
            });

            it("denied: Vault NFT Owner (aka liquidity provider)", async () => {
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .commitDelayedProtocolPerVaultParams(nft)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
            it("denied: Vault NFT Approved (aka strategy)", async () => {
                await expect(
                    this.subject
                        .connect(this.strategySigner)
                        .commitDelayedProtocolPerVaultParams(nft)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
            it("denied: deployer", async () => {
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .commitDelayedProtocolPerVaultParams(nft)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });

            it("denied: random address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });

        describe("edge cases", () => {
            describe("when called twice", () => {
                it("reverts", async () => {
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedProtocolPerVaultParams(nft);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.be.revertedWith(Exceptions.NULL);
                });
            });
            describe("when nothing is staged", () => {
                it("reverts", async () => {
                    await this.deploymentFixture();
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.be.revertedWith(Exceptions.NULL);
                });
            });
            describe("when delay has not elapsed and params have not been commited", () => {
                it("reverts", async () => {
                    await this.deploymentFixture();
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, someParams);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.not.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
            describe("when params have already been set and delay has not elapsed", () => {
                it("reverts", async () => {
                    await this.deploymentFixture();
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, someParams);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.not.be.revertedWith(Exceptions.TIMESTAMP);

                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(nft, someParams);
                    await sleep(this.governanceDelay - 60);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    await sleep(60);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams(nft)
                    ).to.not.be.reverted;
                });
            });
        });
    });
}
