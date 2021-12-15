import { BigNumber, Contract, ethers, Signer } from "ethers";
import { Arbitrary, nat, Random } from "fast-check";
import { type } from "os";
import {
    randomAddress,
    sleep,
    toObject,
    withSigner,
    zeroify,
} from "../library/Helpers";
import { address, pit, RUNS } from "../library/property";
import { equals } from "ramda";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import Exceptions from "../library/Exceptions";
import { generateParams, VaultGovernanceContext } from "./vaultGovernance";
import { deployments } from "hardhat";

export function delayedProtocolParamsBehavior<P, S extends Contract>(
    this: VaultGovernanceContext<S>,
    paramsArb: Arbitrary<P>
) {
    let someParams: P;
    let noneParams: P;
    this.beforeEach(() => {
        ({ someParams, noneParams } = generateParams(paramsArb));
    });

    describe(`#stagedDelayedProtocolParams`, () => {
        it(`returns DelayedProtocolParams staged for commit`, async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolParams(someParams);
            const actualParams =
                await this.subject.stagedDelayedProtocolParams();
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
                        .stageDelayedProtocolParams(params);
                    const actualParams =
                        await this.subject.stagedDelayedProtocolParams();

                    return equals(toObject(actualParams), params);
                }
            );
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).stagedDelayedProtocolParams()
                    ).to.not.be.reverted;
                });
            });
        });
        describe("edge cases", () => {
            describe("when no params are staged for commit", () => {
                it("returns zero struct", async () => {
                    const actualParams =
                        await this.subject.stagedDelayedProtocolParams();
                    expect(noneParams).to.equivalent(actualParams);
                });
            });

            describe("when params were just committed", () => {
                it("returns zero struct", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(someParams);
                    await sleep(this.governanceDelay);
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedProtocolParams();
                    const actualParams =
                        await this.subject.stagedDelayedProtocolParams();
                    expect(noneParams).to.equivalent(actualParams);
                });
            });
        });
    });

    describe(`#delayedProtocolParams`, () => {
        it(`returns current DelayedProtocolParams`, async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolParams(someParams);
            await sleep(this.governanceDelay);
            await this.subject
                .connect(this.admin)
                .commitDelayedProtocolParams();
            const actualParams = await this.subject.delayedProtocolParams();
            expect(someParams).to.equivalent(actualParams);
        });
        describe("properties", () => {
            pit(
                `staging DelayedProtocolParams doesn't change delayedProtocolParams`,
                { numRuns: RUNS.low },
                paramsArb,
                async (params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(params);
                    const actualParams =
                        await this.subject.delayedProtocolParams();

                    return !equals(toObject(actualParams), params);
                }
            );
        });
        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).delayedProtocolParams()
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when no params were committed", () => {
                it("returns non-zero params initialized in constructor", async () => {
                    const actualParams =
                        await this.subject.delayedProtocolParams();
                    expect(actualParams).to.not.be.equivalent(noneParams);
                });
            });
        });
    });

    describe("#stageDelayedProtocolParams", () => {
        it("stages DelayedProtocolParams for commit", async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolParams(someParams);
            const actualParams =
                await this.subject.stagedDelayedProtocolParams();
            expect(someParams).to.be.equivalent(actualParams);
        });
        it("sets delay for commit", async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolParams(someParams);
            expect(
                await this.subject.delayedProtocolParamsTimestamp()
            ).to.be.within(
                this.governanceDelay + this.startTimestamp,
                this.governanceDelay + this.startTimestamp + 60
            );
        });
        it("emits StageDelayedProtocolParams event", async () => {
            await expect(
                this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolParams(someParams)
            ).to.emit(this.subject, "StageDelayedProtocolParams");
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
                                .stageDelayedProtocolParams(params)
                        ).to.be.revertedWith(Exceptions.ADMIN);
                    });
                    return true;
                }
            );
        });

        describe("access control", () => {
            it("allowed: ProtocolGovernance admin", async () => {
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolParams(someParams);
            });

            it("denied: Vault NFT Owner (aka liquidity provider)", async () => {
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .stageDelayedProtocolParams(someParams)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
            it("denied: Vault NFT Approved (aka strategy)", async () => {
                await expect(
                    this.subject
                        .connect(this.strategySigner)
                        .stageDelayedProtocolParams(someParams)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
            it("denied: deployer", async () => {
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .stageDelayedProtocolParams(someParams)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });

            it("denied: random address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .stageDelayedProtocolParams(someParams)
                    ).to.be.revertedWith(Exceptions.ADMIN);
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
                        .stageDelayedProtocolParams(someParams);
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(someOtherParams);
                    const actualParams =
                        await this.subject.stagedDelayedProtocolParams();
                    expect(someOtherParams).to.be.equivalent(actualParams);
                });
            });
            describe("when called with zero params", () => {
                it("succeeds with zero params", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(noneParams);
                    const actualParams =
                        await this.subject.stagedDelayedProtocolParams();
                    expect(noneParams).to.be.equivalent(actualParams);
                });
            });
        });
    });

    describe("#commitDelayedProtocolParams", () => {
        let stagedFixture: Function;
        before(async () => {
            stagedFixture = await deployments.createFixture(async () => {
                await this.deploymentFixture();
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolParams(someParams);
            });
        });
        beforeEach(async () => {
            await stagedFixture();
            await sleep(this.governanceDelay);
        });
        it("commits staged DelayedProtocolParams", async () => {
            await this.subject
                .connect(this.admin)
                .commitDelayedProtocolParams();

            const actualParams = await this.subject.delayedProtocolParams();
            expect(someParams).to.be.equivalent(actualParams);
        });
        it("resets delay for commit", async () => {
            await this.subject
                .connect(this.admin)
                .commitDelayedProtocolParams();
            expect(
                await this.subject.delayedProtocolParamsTimestamp()
            ).to.equal(BigNumber.from(0));
        });
        it("emits CommitDelayedProtocolParams event", async () => {
            await expect(
                await this.subject
                    .connect(this.admin)
                    .commitDelayedProtocolParams()
            ).to.emit(this.subject, "CommitDelayedProtocolParams");
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
                        .stageDelayedProtocolParams(someParams);
                    await sleep(this.governanceDelay);

                    await withSigner(addr, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .commitDelayedProtocolParams()
                        ).to.be.revertedWith(Exceptions.ADMIN);
                    });
                    return true;
                }
            );
            pit(
                "reverts if called before the delay has elapsed",
                { numRuns: RUNS.mid },
                async () => nat((await this.governanceDelay) - 60),
                paramsArb,
                async (delay: number, params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(someParams);
                    await sleep(delay);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolParams()
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
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(someParams);
                    await sleep(this.governanceDelay + 60 + delay);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolParams()
                    ).to.not.be.reverted;
                    return true;
                }
            );
        });

        describe("access control", () => {
            it("allowed: ProtocolGovernance admin", async () => {
                await this.subject
                    .connect(this.admin)
                    .commitDelayedProtocolParams();
            });

            it("denied: Vault NFT Owner (aka liquidity provider)", async () => {
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .commitDelayedProtocolParams()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
            it("denied: Vault NFT Approved (aka strategy)", async () => {
                await expect(
                    this.subject
                        .connect(this.strategySigner)
                        .commitDelayedProtocolParams()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
            it("denied: deployer", async () => {
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .commitDelayedProtocolParams()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });

            it("denied: random address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).commitDelayedProtocolParams()
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });

        describe("edge cases", () => {
            describe("when called twice", () => {
                it("reverts", async () => {
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedProtocolParams();
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolParams()
                    ).to.be.revertedWith(Exceptions.NULL);
                });
            });
            describe("when nothing is staged", () => {
                it("reverts", async () => {
                    await this.deploymentFixture();
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolParams()
                    ).to.be.revertedWith(Exceptions.NULL);
                });
            });
            describe("when delay has not elapsed", () => {
                it("reverts", async () => {
                    await this.deploymentFixture();
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(someParams);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    await sleep(this.governanceDelay - 60);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    await sleep(60);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolParams()
                    ).to.not.be.reverted;
                });
            });
        });
    });
}
