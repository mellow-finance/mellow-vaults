import { BigNumber, Contract, ethers, Signer } from "ethers";
import { Arbitrary, Random } from "fast-check";
import { type } from "os";
import {
    randomAddress,
    sleep,
    toObject,
    withSigner,
    zeroify,
} from "./library/Helpers";
import { address, pit, RUNS } from "./library/property";
import { TestContext } from "./library/setup";
import { mersenne } from "pure-rand";
import { equals } from "ramda";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import Exceptions from "./library/Exceptions";

const random = new Random(mersenne(Math.floor(Math.random() * 100000)));

function generateParams<T extends Object>(
    params: Arbitrary<T>
): { someParams: T; noneParams: T } {
    const someParams: T = params
        .filter((x: T) => !equals(x, zeroify(x)))
        .generate(random).value;
    const noneParams: T = zeroify(someParams);
    return { someParams, noneParams };
}

export type VaultGovernanceContext<S extends Contract> = TestContext<S> & {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

export function vaultGovernanceBehavior<
    DSP,
    SP,
    DPP,
    PP,
    DPPV,
    S extends Contract
>(
    this: VaultGovernanceContext<S>,
    {
        delayedStrategyParams,
        strategyParams,
        delayedProtocolParams,
        protocolParams,
    }: {
        delayedStrategyParams?: Arbitrary<DSP>;
        strategyParams?: Arbitrary<SP>;
        delayedProtocolParams?: Arbitrary<DPP>;
        protocolParams?: Arbitrary<PP>;
        delayedProtocolPerVaultParams?: Arbitrary<DPPV>;
    }
) {
    if (delayedProtocolParams) {
        delayedProtocolParamsBehavior.call(this, delayedProtocolParams);
    }
}

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

        it(`returns DelayedProtocolParams staged for commit`, async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolParams(someParams);
            const actualParams =
                await this.subject.stagedDelayedProtocolParams();
            expect(actualParams).to.be.equivalent(someParams);
        });

        describe("when no params are staged for commit", () => {
            it("returns zero struct", async () => {
                const actualParams =
                    await this.subject.stagedDelayedProtocolParams();
                expect(actualParams).to.equivalent(noneParams);
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
                expect(actualParams).to.equivalent(noneParams);
            });
        });
    });

    describe(`#delayedProtocolParams`, () => {
        pit(
            `just staging params doesn't affect DelayedProtocolParams`,
            { numRuns: RUNS.low },
            paramsArb,
            async (params: P) => {
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolParams(params);
                const actualParams = await this.subject.delayedProtocolParams();

                return !equals(toObject(actualParams), params);
            }
        );

        it(`returns current DelayedProtocolParams`, async () => {
            await this.subject
                .connect(this.admin)
                .stageDelayedProtocolParams(someParams);
            await sleep(this.governanceDelay);
            await this.subject
                .connect(this.admin)
                .commitDelayedProtocolParams();
            const actualParams = await this.subject.delayedProtocolParams();
            expect(actualParams).to.equivalent(someParams);
        });

        describe("when no params were committed", () => {
            it("returns non-zero params initialized in constructor", async () => {
                const actualParams = await this.subject.delayedProtocolParams();
                expect(actualParams).to.not.be.equivalent(noneParams);
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
            expect(actualParams).to.be.equivalent(someParams);
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
            it("denied: Random address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(this.strategySigner)
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
}
