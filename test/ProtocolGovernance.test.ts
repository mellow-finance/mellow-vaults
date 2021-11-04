import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { ContractFactory, Contract, Signer } from "ethers";
import Exceptions from "./library/Exceptions";
import {
    deployProtocolGovernance,
    deployVaultRegistry,
    deployVaultRegistryAndProtocolGovernance,
} from "./library/Deployments";
import { ProtocolGovernance_Params, VaultRegistry } from "./library/Types";
import { BigNumber } from "@ethersproject/bignumber";
import { now, sleep, sleepTo, toObject } from "./library/Helpers";

describe("ProtocolGovernance", () => {
    let protocolGovernance: Contract;
    let deployer: Signer;
    let stranger: Signer;
    let user1: Signer;
    let user2: Signer;
    let user3: Signer;
    let protocolTreasury: Signer;
    let timestamp: number;
    let timeout: number;
    let timeShift: number;
    let params: ProtocolGovernance_Params;
    let initialParams: ProtocolGovernance_Params;
    let paramsZero: ProtocolGovernance_Params;
    let paramsTimeout: ProtocolGovernance_Params;
    let paramsEmpty: ProtocolGovernance_Params;
    let paramsDefault: ProtocolGovernance_Params;
    let defaultGovernanceDelay: number;
    let deploymentFixture: Function;
    let vaultRegistry: VaultRegistry;

    before(async () => {
        [deployer, stranger, user1, user2, user3, protocolTreasury] =
            await ethers.getSigners();
        timeout = 10 ** 4;
        defaultGovernanceDelay = 1;
        timeShift = 10 ** 10;
        timestamp = now() + timeShift;

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();

            const { vaultRegistry, protocolGovernance } =
                await deployVaultRegistryAndProtocolGovernance({
                    name: "VaultRegistry",
                    symbol: "MVR",
                    adminSigner: deployer,
                    treasury: await protocolTreasury.getAddress(),
                });

            params = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(20),
                governanceDelay: BigNumber.from(100),
                strategyPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(20 * 10 ** 9),
                protocolExitFee: BigNumber.from(10 ** 10),
                protocolTreasury: await protocolTreasury.getAddress(),
                vaultRegistry: vaultRegistry.address,
            };

            initialParams = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(10),
                governanceDelay: BigNumber.from(1),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(10 ** 9),
                protocolTreasury: await protocolTreasury.getAddress(),
                vaultRegistry: vaultRegistry.address,
            };

            paramsZero = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(1),
                governanceDelay: BigNumber.from(0),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(10 ** 9),
                protocolTreasury: ethers.constants.AddressZero,
                vaultRegistry: ethers.constants.AddressZero,
            };

            paramsEmpty = {
                permissionless: true,
                maxTokensPerVault: BigNumber.from(0),
                governanceDelay: BigNumber.from(0),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(10 ** 9),
                protocolTreasury: ethers.constants.AddressZero,
                vaultRegistry: vaultRegistry.address,
            };

            paramsDefault = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(0),
                governanceDelay: BigNumber.from(0),
                strategyPerformanceFee: BigNumber.from(0),
                protocolPerformanceFee: BigNumber.from(0),
                protocolExitFee: BigNumber.from(0),
                protocolTreasury: ethers.constants.AddressZero,
                vaultRegistry: ethers.constants.AddressZero,
            };

            paramsTimeout = {
                permissionless: true,
                maxTokensPerVault: BigNumber.from(1),
                governanceDelay: BigNumber.from(timeout),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(10 ** 9),
                protocolTreasury: await user1.getAddress(),
                vaultRegistry: vaultRegistry.address,
            };

            return {
                protocolGovernance: protocolGovernance,
                vaultRegistry: vaultRegistry,
            };
        });
    });

    beforeEach(async () => {
        const protocolGovernanceSystem = await deploymentFixture();
        protocolGovernance = protocolGovernanceSystem.protocolGovernance;
        vaultRegistry = protocolGovernanceSystem.vaultRegistry;
        sleep(defaultGovernanceDelay);
    });

    describe("constructor", () => {
        it("has empty pending claim allow list", async () => {
            expect(await protocolGovernance.claimAllowlist()).to.be.empty;
        });

        it("has no vault governances", async () => {
            expect(await protocolGovernance.vaultGovernances()).to.be.empty;
        });

        it("has empty pending claim allow list add", async () => {
            expect(await protocolGovernance.pendingClaimAllowlistAdd()).to.be
                .empty;
        });

        it("has empty pending vault governances add", async () => {
            expect(await protocolGovernance.pendingVaultGovernancesAdd()).to.be
                .empty;
        });

        it("has no pending params", async () => {
            expect(
                toObject(await protocolGovernance.pendingParams())
            ).to.deep.equal(paramsDefault);
        });

        it("deployer and stranger are not vault governances", async () => {
            expect(
                await protocolGovernance.isVaultGovernance(
                    await deployer.getAddress()
                )
            ).to.be.equal(false);

            expect(
                await protocolGovernance.isVaultGovernance(
                    await stranger.getAddress()
                )
            ).to.be.equal(false);
        });

        it("does not allow deployer to claim", async () => {
            expect(
                await protocolGovernance.isAllowedToClaim(deployer.getAddress())
            ).to.be.equal(false);
        });

        it("does not allow stranger to claim", async () => {
            expect(
                await protocolGovernance.isAllowedToClaim(stranger.getAddress())
            ).to.be.equal(false);
        });

        describe("initial params struct values", () => {
            it("has initial params struct", async () => {
                expect(
                    toObject(await protocolGovernance.params())
                ).to.deep.equal(initialParams);
            });

            it("by default permissionless == false", async () => {
                expect(await protocolGovernance.permissionless()).to.be.equal(
                    initialParams.permissionless
                );
            });

            it("has max tokens per vault", async () => {
                expect(
                    await protocolGovernance.maxTokensPerVault()
                ).to.be.equal(initialParams.maxTokensPerVault);
            });

            it("has governance delay", async () => {
                expect(await protocolGovernance.governanceDelay()).to.be.equal(
                    initialParams.governanceDelay
                );
            });

            it("has strategy performance fee", async () => {
                expect(
                    await protocolGovernance.strategyPerformanceFee()
                ).to.be.equal(initialParams.strategyPerformanceFee);
            });

            it("has protocol performance fee", async () => {
                expect(
                    await protocolGovernance.protocolPerformanceFee()
                ).to.be.equal(initialParams.protocolPerformanceFee);
            });

            it("has protocol exit fee", async () => {
                expect(await protocolGovernance.protocolExitFee()).to.be.equal(
                    initialParams.protocolExitFee
                );
            });

            it("has protocol treasury", async () => {
                expect(await protocolGovernance.protocolTreasury()).to.be.equal(
                    initialParams.protocolTreasury
                );
            });

            it("has vault registry", async () => {
                expect(await protocolGovernance.vaultRegistry()).to.be.equal(
                    initialParams.vaultRegistry
                );
            });
        });
    });

    describe("setPendingParams", () => {
        it("sets the params", () => {
            describe("when called once", () => {
                it("sets the params", async () => {
                    await protocolGovernance.setPendingParams(params);

                    expect(
                        toObject(
                            await protocolGovernance.functions.pendingParams()
                        )
                    ).to.deep.equal(params);
                });
            });

            describe("when called twice", () => {
                it("sets the params", async () => {
                    await protocolGovernance.setPendingParams(paramsTimeout);
                    await protocolGovernance.setPendingParams(paramsZero);

                    expect(
                        toObject(
                            await protocolGovernance.functions.pendingParams()
                        )
                    ).to.deep.equal(paramsZero);
                });
            });
        });

        it("sets governance delay", async () => {
            sleepTo(timestamp);
            await protocolGovernance.setPendingParams(params);
            expect(
                Math.abs(
                    (await protocolGovernance.pendingParamsTimestamp()) -
                        timestamp
                )
            ).to.be.lessThanOrEqual(10);
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .setPendingParams(params)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("commitParams", () => {
        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await protocolGovernance.setPendingParams(paramsZero);

                await expect(
                    protocolGovernance.connect(stranger).commitParams()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when governance delay has not passed", () => {
            describe("when call immediately", () => {
                it("reverts", async () => {
                    await protocolGovernance.setPendingParams(paramsTimeout);

                    sleep(100 * 1000);

                    await protocolGovernance.commitParams();

                    await protocolGovernance.setPendingParams(paramsZero);
                    await expect(
                        protocolGovernance.commitParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });

            describe("when delay has almost passed", () => {
                it("reverts", async () => {
                    await protocolGovernance.setPendingParams(paramsTimeout);

                    sleep(100 * 1000);

                    await protocolGovernance.commitParams();

                    sleep(timeout - 2);

                    await protocolGovernance.setPendingParams(paramsZero);
                    await expect(
                        protocolGovernance.commitParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });

        describe("when governanceDelay is 0 and maxTokensPerVault is 0", () => {
            it("reverts", async () => {
                await protocolGovernance.setPendingParams(paramsEmpty);

                sleep(100 * 1000);

                await expect(
                    protocolGovernance.commitParams()
                ).to.be.revertedWith(Exceptions.EMPTY_PARAMS);
            });
        });

        it("commits params", async () => {
            await protocolGovernance.setPendingParams(paramsZero);

            sleep(100 * 1000);

            await protocolGovernance.commitParams();
            expect(toObject(await protocolGovernance.params())).to.deep.equal(
                paramsZero
            );
        });

        it("deletes pending params", async () => {
            await protocolGovernance.setPendingParams(paramsZero);

            sleep(100 * 1000);

            await protocolGovernance.commitParams();
            expect(
                toObject(await protocolGovernance.pendingParams())
            ).to.deep.equal(paramsDefault);
        });

        describe("when commited twice", () => {
            it("reverts", async () => {
                await protocolGovernance.setPendingParams(paramsZero);

                sleep(100 * 1000);

                await protocolGovernance.commitParams();

                await expect(
                    protocolGovernance.commitParams()
                ).to.be.revertedWith(Exceptions.EMPTY_PARAMS);
            });
        });

        it("deletes pending params timestamp", async () => {
            timestamp += 10 ** 6;

            sleepTo(timestamp);

            await protocolGovernance.setPendingParams(paramsTimeout);

            timestamp += 10 ** 6;
            sleepTo(timestamp);
            await protocolGovernance.commitParams();

            expect(
                await protocolGovernance.pendingParamsTimestamp()
            ).to.be.equal(BigNumber.from(0));
        });
    });

    describe("setPendingClaimAllowlistAdd", () => {
        it("sets pending list", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([
                user1.getAddress(),
                user2.getAddress(),
            ]);

            expect(
                await protocolGovernance.pendingClaimAllowlistAdd()
            ).to.deep.equal([
                await user1.getAddress(),
                await user2.getAddress(),
            ]);
        });

        it("sets correct pending timestamp with zero gonernance delay", async () => {
            timestamp += 10 ** 6;
            sleepTo(timestamp);
            await protocolGovernance.setPendingParams(paramsZero);

            timestamp += 10 ** 6;
            sleepTo(timestamp);
            await protocolGovernance.commitParams();

            await protocolGovernance.setPendingClaimAllowlistAdd([
                user1.getAddress(),
                user2.getAddress(),
            ]);

            expect(
                Math.abs(
                    (await protocolGovernance.pendingClaimAllowlistAddTimestamp()) -
                        timestamp
                )
            ).to.be.lessThanOrEqual(10);
        });

        it("sets correct pending timestamp with non-zero governance delay", async () => {
            timestamp += 10 ** 6;
            sleepTo(timestamp);
            await protocolGovernance.setPendingParams(paramsTimeout);

            timestamp += 10 ** 6;
            sleepTo(timestamp);
            await protocolGovernance.commitParams();

            await protocolGovernance.setPendingClaimAllowlistAdd([
                user1.getAddress(),
                user2.getAddress(),
            ]);

            expect(
                Math.abs(
                    (await protocolGovernance.pendingClaimAllowlistAddTimestamp()) -
                        (timestamp + timeout)
                )
            ).to.be.lessThanOrEqual(10);
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .setPendingClaimAllowlistAdd([])
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("setPendingVaultGovernancesAdd", () => {
        describe("sets pending vault governances", () => {
            describe("when there are no repeating addresses", () => {
                it("sets", async () => {
                    await protocolGovernance.setPendingVaultGovernancesAdd([
                        await user1.getAddress(),
                        await user2.getAddress(),
                    ]);

                    expect(
                        await protocolGovernance.pendingVaultGovernancesAdd()
                    ).to.deep.equal([
                        await user1.getAddress(),
                        await user2.getAddress(),
                    ]);
                });
            });

            describe("when there are repeating addresses", () => {
                it("sets", async () => {
                    await protocolGovernance.setPendingVaultGovernancesAdd([
                        await user1.getAddress(),
                        await user2.getAddress(),
                        await user2.getAddress(),
                        await user1.getAddress(),
                    ]);

                    expect(
                        await protocolGovernance.pendingVaultGovernancesAdd()
                    ).to.deep.equal([
                        await user1.getAddress(),
                        await user2.getAddress(),
                        await user2.getAddress(),
                        await user1.getAddress(),
                    ]);
                });
            });

            it("sets pendingVaultGovernancesAddTimestamp", async () => {
                timestamp += timeShift;
                sleepTo(timestamp);

                await protocolGovernance.setPendingVaultGovernancesAdd([
                    await user1.getAddress(),
                    await user2.getAddress(),
                ]);

                expect(
                    Math.abs(
                        (await protocolGovernance.pendingVaultGovernancesAddTimestamp()) -
                            timestamp
                    )
                ).to.be.lessThanOrEqual(10);
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .setPendingVaultGovernancesAdd([
                            await user1.getAddress(),
                            await user2.getAddress(),
                        ])
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("commitVaultGovernancesAdd", () => {
        describe("when there are no repeating addresses", () => {
            it("sets vault governance add", async () => {
                await protocolGovernance.setPendingVaultGovernancesAdd([
                    await user1.getAddress(),
                    await user2.getAddress(),
                    await user3.getAddress(),
                ]);

                await sleep(100);

                await protocolGovernance.commitVaultGovernancesAdd();

                expect(
                    await protocolGovernance.isVaultGovernance(
                        await user1.getAddress()
                    )
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(
                        await user2.getAddress()
                    )
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(
                        await user3.getAddress()
                    )
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(
                        await stranger.getAddress()
                    )
                ).to.be.equal(false);
            });
        });

        describe("when there are repeating addresses", () => {
            it("sets vault governance add", async () => {
                await protocolGovernance.setPendingVaultGovernancesAdd([
                    await user1.getAddress(),
                    await user2.getAddress(),
                    await user2.getAddress(),
                    await user1.getAddress(),
                    await user3.getAddress(),
                ]);

                await sleep(100);

                await protocolGovernance.commitVaultGovernancesAdd();

                expect(
                    await protocolGovernance.isVaultGovernance(
                        await user1.getAddress()
                    )
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(
                        await user2.getAddress()
                    )
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(
                        await user3.getAddress()
                    )
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(
                        await stranger.getAddress()
                    )
                ).to.be.equal(false);
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await protocolGovernance.setPendingVaultGovernancesAdd([
                    await user1.getAddress(),
                    await user2.getAddress(),
                ]);

                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .commitVaultGovernancesAdd()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when pendingVaultGovernancesAddTimestamp has not passed or has almost passed", () => {
            it("reverts", async () => {
                await protocolGovernance.setPendingParams(params);
                await sleep(10);
                await protocolGovernance.commitParams();
                timestamp += timeShift;
                await sleepTo(timestamp);
                await protocolGovernance.setPendingVaultGovernancesAdd([
                    await user1.getAddress(),
                    await user2.getAddress(),
                ]);

                await expect(
                    protocolGovernance.commitVaultGovernancesAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);

                await sleep(95);
                await expect(
                    protocolGovernance.commitVaultGovernancesAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });

        describe("when pendingVaultGovernancesAddTimestamp has not been set", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance.commitVaultGovernancesAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });
    });

    describe("commitClaimAllowlistAdd", () => {
        describe("appends zero address to list", () => {
            it("appends", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([]);

                sleep(100 * 1000);

                await protocolGovernance.commitClaimAllowlistAdd();
                expect(await protocolGovernance.claimAllowlist()).to.deep.equal(
                    []
                );
            });
        });

        describe("appends one address to list", () => {
            it("appends", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    user1.getAddress(),
                ]);

                sleep(100 * 1000);

                await protocolGovernance.commitClaimAllowlistAdd();
                expect(await protocolGovernance.claimAllowlist()).to.deep.equal(
                    [await user1.getAddress()]
                );
            });
        });

        describe("appends multiple addresses to list", () => {
            it("appends", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    deployer.getAddress(),
                ]);

                sleep(100 * 1000);

                await protocolGovernance.commitClaimAllowlistAdd();

                await protocolGovernance.setPendingClaimAllowlistAdd([
                    user1.getAddress(),
                    user2.getAddress(),
                ]);

                sleep(100 * 1000);

                await protocolGovernance.commitClaimAllowlistAdd();

                expect(await protocolGovernance.claimAllowlist()).to.deep.equal(
                    [
                        await deployer.getAddress(),
                        await user1.getAddress(),
                        await user2.getAddress(),
                    ]
                );
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .commitClaimAllowlistAdd()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when does not have pre-set claim allow list add timestamp", () => {
            it("reverts", async () => {
                timestamp += 10 ** 6;
                sleepTo(timestamp);
                await expect(
                    protocolGovernance.commitClaimAllowlistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });

        describe("when governance delay has not passed", () => {
            it("reverts", async () => {
                timestamp += 10 ** 6;
                sleepTo(timestamp);
                await protocolGovernance.setPendingParams(paramsTimeout);

                timestamp += 10 ** 6;
                sleepTo(timestamp);
                await protocolGovernance.commitParams();

                await protocolGovernance.setPendingClaimAllowlistAdd([
                    user1.getAddress(),
                    user2.getAddress(),
                ]);

                await expect(
                    protocolGovernance.commitClaimAllowlistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });
    });

    describe("removeFromClaimAllowlist", async () => {
        describe("when removing non-existing address", () => {
            it("does nothing", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    user1.getAddress(),
                    user2.getAddress(),
                ]);

                sleep(100 * 1000);

                await protocolGovernance.commitClaimAllowlistAdd();
                await protocolGovernance.removeFromClaimAllowlist(
                    stranger.getAddress()
                );
                expect(await protocolGovernance.claimAllowlist()).to.deep.equal(
                    [await user1.getAddress(), await user2.getAddress()]
                );
            });
        });

        describe("when remove called once", () => {
            it("removes the address", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    deployer.getAddress(),
                    user1.getAddress(),
                    user2.getAddress(),
                ]);

                sleep(100 * 1000);

                await protocolGovernance.commitClaimAllowlistAdd();
                await protocolGovernance.removeFromClaimAllowlist(
                    user1.getAddress()
                );
                expect([
                    (await protocolGovernance.isAllowedToClaim(
                        await deployer.getAddress()
                    )) &&
                        (await protocolGovernance.isAllowedToClaim(
                            await user2.getAddress()
                        )),
                    await protocolGovernance.isAllowedToClaim(
                        await user1.getAddress()
                    ),
                ]).to.deep.equal([true, false]);
            });
        });

        describe("when remove called twice", () => {
            it("removes the addresses", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    deployer.getAddress(),
                    user1.getAddress(),
                    user2.getAddress(),
                ]);
                sleep(100 * 1000);

                await protocolGovernance.commitClaimAllowlistAdd();
                await protocolGovernance.removeFromClaimAllowlist(
                    user1.getAddress()
                );
                await protocolGovernance.removeFromClaimAllowlist(
                    user2.getAddress()
                );
                expect([
                    await protocolGovernance.isAllowedToClaim(
                        await deployer.getAddress()
                    ),
                    (await protocolGovernance.isAllowedToClaim(
                        await user1.getAddress()
                    )) &&
                        (await protocolGovernance.isAllowedToClaim(
                            await user2.getAddress()
                        )),
                ]).to.deep.equal([true, false]);
            });
        });

        describe("when remove called twice on the same address", () => {
            it("removes the address and does not fail then", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    deployer.getAddress(),
                    user1.getAddress(),
                    user2.getAddress(),
                ]);

                sleep(100 * 1000);

                await protocolGovernance.commitClaimAllowlistAdd();
                await protocolGovernance.removeFromClaimAllowlist(
                    user2.getAddress()
                );
                await protocolGovernance.removeFromClaimAllowlist(
                    user2.getAddress()
                );
                expect([
                    (await protocolGovernance.isAllowedToClaim(
                        await deployer.getAddress()
                    )) &&
                        (await protocolGovernance.isAllowedToClaim(
                            await user1.getAddress()
                        )),
                    await protocolGovernance.isAllowedToClaim(
                        await user2.getAddress()
                    ),
                ]).to.deep.equal([true, false]);
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .removeFromClaimAllowlist(deployer.getAddress())
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("removeFromVaultGovernances", () => {
        describe("when called by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .removeFromVaultGovernances(await user1.getAddress())
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when address is not in vault governances", () => {
            it("does not fail", async () => {
                await protocolGovernance.setPendingVaultGovernancesAdd([
                    await user1.getAddress(),
                    await user2.getAddress(),
                ]);
                await sleep(100);
                await protocolGovernance.commitVaultGovernancesAdd();

                await expect(
                    protocolGovernance.removeFromVaultGovernances(
                        await user3.getAddress()
                    )
                ).to.not.be.reverted;

                expect(
                    (await protocolGovernance.vaultGovernances()).length
                ).to.be.equal(2);
            });
        });

        describe("when address is a vault governance", () => {
            describe("when attempt to remove one address", () => {
                it("removes", async () => {
                    await protocolGovernance.setPendingVaultGovernancesAdd([
                        await user1.getAddress(),
                        await user2.getAddress(),
                        await user3.getAddress(),
                    ]);
                    await sleep(100);
                    await protocolGovernance.commitVaultGovernancesAdd();

                    await expect(
                        protocolGovernance.removeFromVaultGovernances(
                            await user3.getAddress()
                        )
                    ).to.not.be.reverted;
                    expect(
                        await protocolGovernance.isVaultGovernance(
                            await user3.getAddress()
                        )
                    ).to.be.equal(false);
                    expect(
                        await protocolGovernance.isVaultGovernance(
                            await user2.getAddress()
                        )
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isVaultGovernance(
                            await user1.getAddress()
                        )
                    ).to.be.equal(true);
                });
            });
            describe("when attempt to remove multiple addresses", () => {
                it("removes", async () => {
                    await protocolGovernance.setPendingVaultGovernancesAdd([
                        await user1.getAddress(),
                        await user2.getAddress(),
                        await user3.getAddress(),
                    ]);
                    await sleep(100);
                    await protocolGovernance.commitVaultGovernancesAdd();

                    await expect(
                        protocolGovernance.removeFromVaultGovernances(
                            await user3.getAddress()
                        )
                    ).to.not.be.reverted;
                    await expect(
                        protocolGovernance.removeFromVaultGovernances(
                            await user2.getAddress()
                        )
                    ).to.not.be.reverted;
                    await expect(
                        protocolGovernance.removeFromVaultGovernances(
                            await user3.getAddress()
                        )
                    ).to.not.be.reverted;

                    expect(
                        await protocolGovernance.isVaultGovernance(
                            await user3.getAddress()
                        )
                    ).to.be.equal(false);
                    expect(
                        await protocolGovernance.isVaultGovernance(
                            await user2.getAddress()
                        )
                    ).to.be.equal(false);
                    expect(
                        await protocolGovernance.isVaultGovernance(
                            await user1.getAddress()
                        )
                    ).to.be.equal(true);
                });
            });
        });
    });
});
