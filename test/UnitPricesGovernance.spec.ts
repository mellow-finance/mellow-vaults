import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { UnitPricesGovernance } from "./types/UnitPricesGovernance";
import { contract } from "./library/setup";
import Exceptions from "./library/Exceptions";
import {
    withSigner,
    randomAddress,
    now,
    sleepTo,
    sleep,
} from "./library/Helpers";

type CustomContext = {};
type DeployOptions = {};

contract<UnitPricesGovernance, DeployOptions, CustomContext>(
    "UnitPricesGovernance",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const factory = await ethers.getContractFactory(
                        "UnitPricesGovernance"
                    );
                    this.subject = (await factory.deploy(
                        this.admin.address
                    )) as UnitPricesGovernance;
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
            this.DELAY = Number(await this.subject.DELAY());
            this.startTimestamp = now();
            await sleepTo(this.startTimestamp);
        });

        describe("UnitPricesGovernance", () => {
            describe("#stageUnitPrices", () => {
                it(`stages unit price for the first time,
                    updates respective #stagedUnitPrices
                    and #stagedUnitPricesTimestamps`, async () => {
                    const token = randomAddress();
                    await this.subject
                        .connect(this.admin)
                        .stageUnitPrice(token, 1);
                    expect(await this.subject.stagedUnitPrices(token)).to.eq(1);
                    expect(
                        await this.subject.stagedUnitPricesTimestamps(token)
                    ).to.eq(this.startTimestamp + 1);
                });

                it(`restages unit price,
                    updates respective #stagedUnitPrices
                    and #stagedUnitPricesTimestamps`, async () => {
                    const token = randomAddress();
                    await this.subject
                        .connect(this.admin)
                        .stageUnitPrice(token, 1);
                    await this.subject
                        .connect(this.admin)
                        .commitUnitPrice(token);
                    await this.subject
                        .connect(this.admin)
                        .stageUnitPrice(token, 2);
                    expect(await this.subject.stagedUnitPrices(token)).to.eq(2);
                    expect(
                        await this.subject.stagedUnitPricesTimestamps(token)
                    ).to.eq(this.startTimestamp + this.DELAY + 3);
                });

                it("emits UnitPriceStaged event", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageUnitPrice(randomAddress(), 1)
                    ).to.emit(this.subject, "UnitPriceStaged");
                });

                describe("edge cases", () => {
                    describe("when token is zero address", () => {
                        it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .stageUnitPrice(
                                        ethers.constants.AddressZero,
                                        1
                                    )
                            ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                        });
                    });

                    describe("when value is zero", () => {
                        it(`ignores the delay for #stagedUnitPricesTimestamps`, async () => {
                            const token = randomAddress();
                            await this.subject
                                .connect(this.admin)
                                .stageUnitPrice(token, 0);
                            expect(
                                await this.subject.stagedUnitPricesTimestamps(
                                    token
                                )
                            ).to.eq(this.startTimestamp + 1);
                        });
                    });
                });

                describe("access control", () => {
                    xit("allowed: governance admin", async () => {});
                    it("denied: random address", async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .stageUnitPrice(randomAddress(), 1)
                            ).to.be.revertedWith(Exceptions.FORBIDDEN);
                        });
                    });
                });
            });

            describe("#rollbackUnitPrice", () => {
                it(`rolls back staged unit prices,
                    clears respective #stagedUnitPrices
                    and #stagedUnitPricesTimestamps`, async () => {
                    const token = randomAddress();
                    await this.subject
                        .connect(this.admin)
                        .stageUnitPrice(token, 1);
                    await this.subject
                        .connect(this.admin)
                        .rollbackUnitPrice(token);
                    expect(await this.subject.stagedUnitPrices(token)).to.eq(0);
                    expect(
                        await this.subject.stagedUnitPricesTimestamps(token)
                    ).to.eq(0);
                });

                it("emits UnitPriceRolledBack event", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rollbackUnitPrice(randomAddress())
                    ).to.emit(this.subject, "UnitPriceRolledBack");
                });

                describe("access control", () => {
                    xit("allowed: governance admin", async () => {});
                    it("denied: random address", async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .rollbackUnitPrice(randomAddress())
                            ).to.be.revertedWith(Exceptions.FORBIDDEN);
                        });
                    });
                });
            });

            describe("#commitUnitPrice", () => {
                it(`commits staged unit price,
                    clears respective #stagedUnitPrices,
                    #stagedUnitPricesTimestamps
                    and updates respective #unitPrices`, async () => {
                    const token = randomAddress();
                    await this.subject
                        .connect(this.admin)
                        .stageUnitPrice(token, 1);
                    await sleep(this.DELAY);
                    await this.subject
                        .connect(this.admin)
                        .commitUnitPrice(token);
                    expect(await this.subject.stagedUnitPrices(token)).to.eq(0);
                    expect(
                        await this.subject.stagedUnitPricesTimestamps(token)
                    ).to.eq(0);
                    expect(await this.subject.unitPrices(token)).to.eq(1);
                });

                it("emits UnitPriceCommitted event", async () => {
                    const token = randomAddress();
                    await this.subject
                        .connect(this.admin)
                        .stageUnitPrice(token, 1);
                    await sleep(this.DELAY);
                    await expect(
                        this.subject.connect(this.admin).commitUnitPrice(token)
                    ).to.emit(this.subject, "UnitPriceCommitted");
                });

                describe("edge cases", () => {
                    describe("if not staged", () => {
                        it(`reverts with ${Exceptions.INVALID_STATE}`, async () => {
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .commitUnitPrice(randomAddress())
                            ).to.be.revertedWith(Exceptions.INVALID_STATE);
                        });
                    });

                    describe("if not surpassed the delay", () => {
                        it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                            const token = randomAddress();
                            await this.subject
                                .connect(this.admin)
                                .stageUnitPrice(token, 1);
                            await this.subject
                                .connect(this.admin)
                                .commitUnitPrice(token);
                            // restage unit price
                            await this.subject
                                .connect(this.admin)
                                .stageUnitPrice(token, 2);
                            await sleep(this.DELAY - 10);
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .commitUnitPrice(token)
                            ).to.be.revertedWith(Exceptions.TIMESTAMP);
                        });
                    });
                });

                describe("access control", () => {
                    xit("allowed: governance admin", async () => {});
                    it("denied: random address", async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            const token = randomAddress();
                            await this.subject
                                .connect(this.admin)
                                .stageUnitPrice(token, 1);
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .commitUnitPrice(token)
                            ).to.be.revertedWith(Exceptions.FORBIDDEN);
                        });
                    });
                });
            });
        });
    }
);
