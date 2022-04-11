import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import { TestContext } from "../library/setup";
import Exceptions from "../library/Exceptions";
import {
    randomAddress,
    sleep,
    withSigner,
    toObject,
    now,
    sleepTo,
    zeroify,
} from "../library/Helpers";
import {
    VAULT_INTERFACE_ID,
    VALIDATOR_INTERFACE_ID,
} from "../library/Constants";
import { ethers } from "hardhat";
import { randomBytes } from "crypto";

export type ValidatorContext<S extends Contract, F> = TestContext<S, F>;

export function ValidatorBehaviour<S extends Contract>(
    this: ValidatorContext<S, {}>,
    {}: {}
) {
    describe("#constructor", () => {
        it("deploys a new contract", async () => {
            expect(this.subject.address).to.not.eql(
                ethers.constants.AddressZero
            );
        });
    });

    describe("#stagedValidatorParams", () => {
        it("allowed: any address", async () => {
            await withSigner(randomAddress(), async (signer) => {
                await expect(
                    this.subject.connect(signer).stagedValidatorParams()
                ).to.not.be.reverted;
            });
        });
    });
    describe("#stagedValidatorParamsTimestamp", () => {
        it("allowed: any address", async () => {
            await withSigner(randomAddress(), async (signer) => {
                await expect(
                    this.subject
                        .connect(signer)
                        .stagedValidatorParamsTimestamp()
                ).to.not.be.reverted;
            });
        });
    });
    describe("#validatorParams", () => {
        it("allowed: any address", async () => {
            await withSigner(randomAddress(), async (signer) => {
                await expect(this.subject.connect(signer).validatorParams()).to
                    .not.be.reverted;
            });
        });
    });

    describe("#validatorParams", () => {
        it("allowed: any address", async () => {
            await withSigner(randomAddress(), async (signer) => {
                await expect(this.subject.connect(signer).validatorParams()).to
                    .not.be.reverted;
            });
        });
    });

    describe("#stageValidatorParams", () => {
        beforeEach(async () => {
            this.stagingParams = { protocolGovernance: randomAddress() };
        });

        it("emits StagedValidatorParams", async () => {
            await withSigner(this.admin.address, async (signer) => {
                await expect(
                    this.subject
                        .connect(signer)
                        .stageValidatorParams(this.stagingParams)
                ).to.emit(this.subject, "StagedValidatorParams");
            });
        });

        it("updates StagedValidatorParams", async () => {
            await withSigner(this.admin.address, async (signer) => {
                await this.subject
                    .connect(signer)
                    .stageValidatorParams(this.stagingParams);
                await expect(
                    toObject(
                        await this.subject
                            .connect(signer)
                            .stagedValidatorParams()
                    )
                ).to.deep.eq(this.stagingParams);
            });
        });

        it("updates StagedValidatorParamsTimestamp", async () => {
            await withSigner(this.admin.address, async (signer) => {
                let currentTimestamp = BigNumber.from(now());
                await sleepTo(currentTimestamp);
                await this.subject
                    .connect(signer)
                    .stageValidatorParams(this.stagingParams);
                await expect(
                    await this.subject
                        .connect(signer)
                        .stagedValidatorParamsTimestamp()
                ).to.eq(
                    currentTimestamp
                        .add(await this.protocolGovernance.governanceDelay())
                        .add(1)
                );
            });
        });

        describe("access control", () => {
            it("forbidden: not an admin", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .stageValidatorParams(this.stagingParams)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });

            it("allowed: admin", async () => {
                await withSigner(this.admin.address, async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .stageValidatorParams(this.stagingParams)
                    ).to.not.be.reverted;
                });
            });
        });
    });

    describe("#commitValidatorParams", () => {
        beforeEach(async () => {
            await withSigner(this.admin.address, async (signer) => {
                this.stagingParams = { protocolGovernance: randomAddress() };
                await this.subject
                    .connect(signer)
                    .stageValidatorParams(this.stagingParams);
            });
        });

        it("emits CommittedValidatorParams", async () => {
            await withSigner(this.admin.address, async (signer) => {
                await sleep(await this.protocolGovernance.governanceDelay());
                await expect(
                    this.subject.connect(signer).commitValidatorParams()
                ).to.emit(this.subject, "CommittedValidatorParams");
            });
        });

        it("deletes stagedValidatorParamsTimestamp", async () => {
            await withSigner(this.admin.address, async (signer) => {
                await expect(
                    await this.subject
                        .connect(signer)
                        .stagedValidatorParamsTimestamp()
                ).to.not.eq(BigNumber.from(0));
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.subject.connect(signer).commitValidatorParams();
                await expect(
                    await this.subject
                        .connect(signer)
                        .stagedValidatorParamsTimestamp()
                ).to.eq(BigNumber.from(0));
            });
        });

        it("deletes stagedValidatorParams", async () => {
            await withSigner(this.admin.address, async (signer) => {
                await expect(
                    toObject(
                        await this.subject
                            .connect(signer)
                            .stagedValidatorParams()
                    )
                ).to.not.deep.eq(zeroify(this.stagingParams));
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.subject.connect(signer).commitValidatorParams();
                await expect(
                    toObject(
                        await this.subject
                            .connect(signer)
                            .stagedValidatorParams()
                    )
                ).to.deep.eq(zeroify(this.stagingParams));
            });
        });

        it("updates validatorParams", async () => {
            await withSigner(this.admin.address, async (signer) => {
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.subject.connect(signer).commitValidatorParams();
                await expect(
                    toObject(
                        await this.subject.connect(signer).validatorParams()
                    )
                ).to.deep.eq(this.stagingParams);
            });
        });
        describe("edge cases:", async () => {
            describe("commit earlier than staging timestamp", async () => {
                it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                    await withSigner(this.admin.address, async (signer) => {
                        await sleep(
                            (
                                await this.protocolGovernance.governanceDelay()
                            ).sub(2)
                        );
                        await expect(
                            this.subject.connect(signer).commitValidatorParams()
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    });
                });
            });
        });

        describe("access control", () => {
            it("forbidden: not an admin", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject.connect(signer).commitValidatorParams()
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });

            it("allowed: admin", async () => {
                await withSigner(this.admin.address, async (signer) => {
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await expect(
                        this.subject.connect(signer).commitValidatorParams()
                    ).to.not.be.reverted;
                });
            });
        });
    });

    describe("#supportsInterface", () => {
        it(`returns true if this contract supports ${VALIDATOR_INTERFACE_ID}`, async () => {
            await withSigner(this.admin.address, async (signer) => {
                await expect(
                    await this.subject
                        .connect(signer)
                        .supportsInterface(VALIDATOR_INTERFACE_ID)
                ).to.be.true;
            });
        });
        describe("edge cases:", async () => {
            describe(`when contract does not support given interface`, async () => {
                it("returns false", async () => {
                    await withSigner(this.admin.address, async (signer) => {
                        await expect(
                            await this.subject
                                .connect(signer)
                                .supportsInterface(VAULT_INTERFACE_ID)
                        ).to.be.false;
                    });
                });
            });
        });

        describe("access control", async () => {
            it("allow: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .supportsInterface(randomBytes(4))
                    ).to.be.not.reverted;
                });
            });
        });
    });
}
