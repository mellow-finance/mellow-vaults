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
import { mersenne } from "pure-rand";
import { uint8 } from "../library/property";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import Exceptions from "../library/Exceptions";
import { generateParams, VaultGovernanceContext } from "./vaultGovernance";
import { deployments } from "hardhat";

const random = new Random(mersenne(Math.floor(Math.random() * 100000)));

export function delayedProtocolPerVaultParamsBehaviour<P, S extends Contract, F>(
    this: VaultGovernanceContext<S, F>,
    paramsArb: Arbitrary<P>
) {
    let someParams: P;
    let noneParams: P;
    let nft: BigNumber;
    this.beforeEach(() => {
        ({ someParams, noneParams } = generateParams(paramsArb));
        nft = uint8.filter(x => x.lt(5)).generate(random).value; // TODO: max vaultsCount() 
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
                async (params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(params);
                    const actualParams =
                        await this.subject.stagedDelayedProtocolPerVaultParams();

                    return equals(toObject(actualParams), params);
                }
            );
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).stagedDelayedProtocolPerVaultParams()
                    ).to.not.be.reverted;
                });
            });
        });
        describe("edge cases", () => {
            describe("when no params are staged for commit", () => {
                it("returns zero struct", async () => {
                    const actualParams =
                        await this.subject.stagedDelayedProtocolPerVaultParams();
                    expect(noneParams).to.equivalent(actualParams);
                });
            });

            describe("when params were just committed", () => {
                it("returns zero struct", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(someParams);
                    await sleep(this.governanceDelay);
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedProtocolPerVaultParams();
                    const actualParams =
                        await this.subject.stagedDelayedProtocolPerVaultParams();
                    expect(noneParams).to.equivalent(actualParams);
                });
            });
        });
    });

    describe(`#delayedProtocolPerVaultParams`, () => {
        it(`returns current DelayedProtocolPerVaultParams`, async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolPerVaultParams(someParams);
            await sleep(this.governanceDelay);
            await this.subject
                .connect(this.admin)
                .commitDelayedProtocolPerVaultParams();
            const actualParams = await this.subject.delayedProtocolPerVaultParams();
            expect(someParams).to.equivalent(actualParams);
        });
        describe("properties", () => {
            pit(
                `staging DelayedProtocolPerVaultParams doesn't change delayedProtocolPerVaultParams`,
                { numRuns: RUNS.low },
                paramsArb,
                async (params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(params);
                    const actualParams =
                        await this.subject.delayedProtocolPerVaultParams();

                    return !equals(toObject(actualParams), params);
                }
            );
        });
        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).delayedProtocolPerVaultParams()
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when no params were committed", () => {
                it("returns non-zero params initialized in constructor", async () => {
                    const actualParams =
                        await this.subject.delayedProtocolPerVaultParams();
                    expect(actualParams).to.not.be.equivalent(noneParams);
                });
            });
        });
    });

    describe("#stageDelayedProtocolPerVaultParams", () => {
        it("stages DelayedProtocolPerVaultParams for commit", async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolPerVaultParams(someParams);
            const actualParams =
                await this.subject.stagedDelayedProtocolPerVaultParams();
            expect(someParams).to.be.equivalent(actualParams);
        });
        it("sets delay for commit", async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolPerVaultParams(someParams);
            expect(
                await this.subject.delayedProtocolPerVaultParamsTimestamp()
            ).to.be.within(
                this.governanceDelay + this.startTimestamp,
                this.governanceDelay + this.startTimestamp + 60
            );
        });
        it("emits StageDelayedProtocolParams event", async () => {
            await expect(
                this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolPerVaultParams(someParams)
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
                                .stageDelayedProtocolPerVaultParams(params)
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
                    .stageDelayedProtocolPerVaultParams(someParams);
            });

            it("denied: Vault NFT Owner (aka liquidity provider)", async () => {
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .stageDelayedProtocolPerVaultParams(someParams)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
            it("denied: Vault NFT Approved (aka strategy)", async () => {
                await expect(
                    this.subject
                        .connect(this.strategySigner)
                        .stageDelayedProtocolPerVaultParams(someParams)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
            it("denied: deployer", async () => {
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .stageDelayedProtocolPerVaultParams(someParams)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });

            it("denied: random address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .stageDelayedProtocolPerVaultParams(someParams)
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
            stagedFixture = deployments.createFixture(async () => {
                await this.deploymentFixture();
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolParams(nft, someParams);
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
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
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
                        .stageDelayedProtocolPerVaultParams(someParams);
                    await sleep(delay);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams()
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
                        .stageDelayedProtocolPerVaultParams(someParams);
                    await sleep(this.governanceDelay + 60 + delay);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams()
                    ).to.not.be.reverted;
                    return true;
                }
            );
        });

        describe("access control", () => {
            it("allowed: ProtocolGovernance admin", async () => {
                await this.subject
                    .connect(this.admin)
                    .commitDelayedProtocolPerVaultParams();
            });

            it("denied: Vault NFT Owner (aka liquidity provider)", async () => {
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .commitDelayedProtocolPerVaultParams()
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
            it("denied: Vault NFT Approved (aka strategy)", async () => {
                await expect(
                    this.subject
                        .connect(this.strategySigner)
                        .commitDelayedProtocolPerVaultParams()
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
            it("denied: deployer", async () => {
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .commitDelayedProtocolPerVaultParams()
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });

            it("denied: random address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).commitDelayedProtocolPerVaultParams()
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });

        describe("edge cases", () => {
            describe("when called twice", () => {
                it("reverts", async () => {
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedProtocolPerVaultParams();
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams()
                    ).to.be.revertedWith(Exceptions.NULL);
                });
            });
            describe("when nothing is staged", () => {
                it("reverts", async () => {
                    await this.deploymentFixture();
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams()
                    ).to.be.revertedWith(Exceptions.NULL);
                });
            });
            describe("when delay has not elapsed", () => {
                it("reverts", async () => {
                    await this.deploymentFixture();
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(someParams);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    await sleep(this.governanceDelay - 60);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    await sleep(60);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitDelayedProtocolPerVaultParams()
                    ).to.not.be.reverted;
                });
            });
        });
    });
}
