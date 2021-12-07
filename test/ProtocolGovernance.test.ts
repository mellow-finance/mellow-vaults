import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { Contract, Signer } from "ethers";
import { BigNumber } from "@ethersproject/bignumber";
import Exceptions from "./library/Exceptions";
import { ParamsStruct, ProtocolGovernance } from "./types/ProtocolGovernance";
import { deployERC20Tokens } from "./library/Deployments";
import { now, sleep, sleepTo, toObject, withSigner } from "./library/Helpers";
import { VaultRegistry } from "./types";

describe("ProtocolGovernance", () => {
    const SECONDS_PER_DAY = 60 * 60 * 24;

    let protocolGovernance: ProtocolGovernance;
    let vaultRegistry: VaultRegistry;
    let deployer: string;
    let admin: string;
    let stranger: string;
    let user1: string;
    let user2: string;
    let user3: string;
    let treasury: string;
    let timestamp: number;
    let timeout: number;
    let timeShift: number;
    let params: ParamsStruct;
    let initialParams: ParamsStruct;
    let paramsZero: ParamsStruct;
    let paramsTimeout: ParamsStruct;
    let paramsEmpty: ParamsStruct;
    let paramsDefault: ParamsStruct;
    let paramsTooLong: ParamsStruct;
    let defaultGovernanceDelay: number;
    let deploymentFixture: Function;
    let tokens: Contract[];
    let wbtc: string;
    let weth: string;
    let usdc: string;

    before(async () => {
        timeout = 10 **4;
        defaultGovernanceDelay = 1;
        timeShift = 10 ** 10;
        timestamp = now() + timeShift;

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            const {
                deployer: d,
                admin: a,
                stranger: s,
                user1: u1,
                user2: u2,
                user3: u3,
                treasury: t,
                weth: we,
                wbtc: wb,
                usdc: us,
            } = await getNamedAccounts();
            [
                deployer,
                admin,
                stranger,
                user1,
                user2,
                user3,
                treasury,
                wbtc,
                weth,
                usdc,
            ] = [d, a, s, u1, u2, u3, t, wb, we, us];

            protocolGovernance = await ethers.getContract("ProtocolGovernance");
            vaultRegistry = await ethers.getContract("VaultRegistry");

            params = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(10),
                governanceDelay: BigNumber.from(100),
                protocolTreasury: treasury,
            };

            initialParams = {
                permissionless: true,
                maxTokensPerVault: BigNumber.from(10),
                governanceDelay: BigNumber.from(SECONDS_PER_DAY), // 1 day
                protocolTreasury: treasury,
            };

            paramsZero = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(1),
                governanceDelay: BigNumber.from(0),
                protocolTreasury: treasury,
            };

            paramsEmpty = {
                permissionless: true,
                maxTokensPerVault: BigNumber.from(0),
                governanceDelay: BigNumber.from(0),
                protocolTreasury: treasury,
            };

            paramsDefault = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(0),
                governanceDelay: BigNumber.from(0),
                protocolTreasury: ethers.constants.AddressZero,
            };

            paramsTimeout = {
                permissionless: true,
                maxTokensPerVault: BigNumber.from(1),
                governanceDelay: BigNumber.from(timeout),
                protocolTreasury: treasury,
            };

            paramsTooLong = {
                permissionless: true,
                maxTokensPerVault: BigNumber.from(1),
                governanceDelay: BigNumber.from(SECONDS_PER_DAY * 10),
                protocolTreasury: treasury,
            };

            tokens = await deployERC20Tokens(3);

            return {
                protocolGovernance: protocolGovernance,
                vaultRegistry: vaultRegistry,
            };
        });
    });

    beforeEach(async () => {
        const protocolGovernanceSystem = await deploymentFixture();
        protocolGovernance = protocolGovernanceSystem.protocolGovernance;
        await sleep(Number(await protocolGovernance.governanceDelay()));
    });

    describe("constructor", () => {
        it("creates GatewayVaultGovernance", async () => {
            expect(protocolGovernance.address).not.to.be.equal(
                ethers.constants.AddressZero
            );
        });
    });

    describe("maxTokensPerVault", () => {
        it("returns correct vaulue", async () => {
            expect(await protocolGovernance.maxTokensPerVault()).to.be.equal(
                10
            );
        });
    });

    describe("setPendingParams", () => {
        describe("when governance delay is greater than max governance delay", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance.connect(signer).setPendingParams(paramsTooLong);
                    await sleep(await protocolGovernance.governanceDelay());
                    await protocolGovernance.connect(signer).commitParams();
                    await expect(
                        protocolGovernance.connect(signer).setPendingParams(params)
                    ).to.be.revertedWith(Exceptions.MAX_GOVERNANCE_DELAY);
                });
            });
        });
        describe("when called once", () => {
            it("sets the params", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingParams(params);
                });

                expect(
                    toObject(await protocolGovernance.functions.pendingParams())
                ).to.deep.equal(params);
            });
        });

        describe("when called twice", () => {
            it("sets the params", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingParams(paramsTimeout);
                    await protocolGovernance
                        .connect(signer)
                        .setPendingParams(paramsZero);
                });

                expect(
                    toObject(await protocolGovernance.functions.pendingParams())
                ).to.deep.equal(paramsZero);
            });
        });
    });

    it("sets governance delay", async () => {
        timestamp += timeShift;
        await sleepTo(timestamp);
        await withSigner(admin, async (sender) => {
            await protocolGovernance.connect(sender).setPendingParams(params);
        });
        expect(
            Math.abs(
                Number(await protocolGovernance.pendingParamsTimestamp()) -
                    timestamp -
                    Number(await protocolGovernance.governanceDelay())
            )
        ).to.be.lessThanOrEqual(10);
    });

    describe("when callen by not admin", () => {
        it("reverts", async () => {
            await withSigner(stranger, async (signer) => {
                await expect(
                    protocolGovernance.connect(signer).setPendingParams(params)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("commitParams", () => {
        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingParams(paramsZero);
                });
                await withSigner(stranger, async (signer) => {
                    await expect(
                        protocolGovernance.connect(signer).commitParams()
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });

        describe("when governance delay has not passed", () => {
            describe("when call immediately", () => {
                it("reverts", async () => {
                    await withSigner(admin, async (signer) => {
                        await protocolGovernance
                            .connect(signer)
                            .setPendingParams(paramsTimeout);
                        sleep(100 * 1000);

                        await protocolGovernance.connect(signer).commitParams();

                        await protocolGovernance
                            .connect(signer)
                            .setPendingParams(paramsZero);
                        await expect(
                            protocolGovernance.connect(signer).commitParams()
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    });
                });
            });

            describe("when delay has almost passed", () => {
                it("reverts", async () => {
                    await withSigner(admin, async (sender) => {
                        await protocolGovernance
                            .connect(sender)
                            .setPendingParams(paramsTimeout);

                        await sleep(100 * 1000);

                        await protocolGovernance.connect(sender).commitParams();

                        await sleep(timeout - 2);

                        await protocolGovernance
                            .connect(sender)
                            .setPendingParams(paramsZero);
                        await expect(
                            protocolGovernance.connect(sender).commitParams()
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    });
                });
            });
        });

        describe("when governanceDelay is 0 and maxTokensPerVault is 0", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingParams(paramsEmpty);

                    await sleep(100 * 1000);

                    await expect(
                        protocolGovernance.connect(signer).commitParams()
                    ).to.be.revertedWith(Exceptions.EMPTY_PARAMS);
                });
            });
        });

        it("commits params", async () => {
            await withSigner(admin, async (signer) => {
                await protocolGovernance
                    .connect(signer)
                    .setPendingParams(paramsZero);

                await sleep(100 * 1000);

                await protocolGovernance.connect(signer).commitParams();
                expect(
                    toObject(await protocolGovernance.params())
                ).to.deep.equal(paramsZero);
            });
        });

        it("deletes pending params", async () => {
            await withSigner(admin, async (signer) => {
                await protocolGovernance
                    .connect(signer)
                    .setPendingParams(paramsZero);

                await sleep(100 * 1000);

                await protocolGovernance.connect(signer).commitParams();
                expect(
                    toObject(await protocolGovernance.pendingParams())
                ).to.deep.equal(paramsDefault);
            });
        });

        describe("when commited twice", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingParams(paramsZero);

                    await sleep(100 * 1000);

                    await protocolGovernance.connect(signer).commitParams();

                    await expect(
                        protocolGovernance.connect(signer).commitParams()
                    ).to.be.revertedWith(Exceptions.EMPTY_PARAMS);
                });
            });
        });

        it("deletes pending params timestamp", async () => {
            await withSigner(admin, async (signer) => {
                timestamp += 10 ** 6;

                await sleepTo(timestamp);

                await protocolGovernance
                    .connect(signer)
                    .setPendingParams(paramsTimeout);

                timestamp += 10 ** 6;
                await sleepTo(timestamp);
                await protocolGovernance.connect(signer).commitParams();

                expect(
                    await protocolGovernance
                        .connect(signer)
                        .pendingParamsTimestamp()
                ).to.be.equal(BigNumber.from(0));
            });
        });
    });

    describe("setPendingClaimAllowlistAdd", () => {
        it("sets pending list", async () => {
            await withSigner(admin, async (signer) => {
                await protocolGovernance
                    .connect(signer)
                    .setPendingClaimAllowlistAdd([deployer, stranger]);

                expect(
                    await protocolGovernance
                        .connect(signer)
                        .pendingClaimAllowlistAdd()
                ).to.deep.equal([deployer, stranger]);
            });
        });

        it("sets correct pending timestamp with zero gonernance delay", async () => {
            await withSigner(admin, async (signer) => {
                timestamp += 10 ** 6;
                sleepTo(timestamp);
                await protocolGovernance
                    .connect(signer)
                    .setPendingParams(paramsZero);

                timestamp += 10 ** 6;
                sleepTo(timestamp);
                await protocolGovernance.connect(signer).commitParams();

                await protocolGovernance
                    .connect(signer)
                    .setPendingClaimAllowlistAdd([user1, user2]);

                expect(
                    Math.abs(
                        Number(
                            await protocolGovernance.pendingClaimAllowlistAddTimestamp()
                        ) - timestamp
                    )
                ).to.be.lessThanOrEqual(SECONDS_PER_DAY + 1);
            });
        });

        it("sets correct pending timestamp with non-zero governance delay", async () => {
            await withSigner(admin, async (signer) => {
                timestamp += 10 ** 6;
                sleepTo(timestamp);
                await protocolGovernance
                    .connect(signer)
                    .setPendingParams(paramsTimeout);

                timestamp += 10 ** 6;
                sleepTo(timestamp);
                await protocolGovernance.connect(signer).commitParams();

                await protocolGovernance
                    .connect(signer)
                    .setPendingClaimAllowlistAdd([user1, user2]);

                expect(
                    Math.abs(
                        Number(
                            await protocolGovernance.pendingClaimAllowlistAddTimestamp()
                        ) -
                            (timestamp + timeout)
                    )
                ).to.be.lessThanOrEqual(SECONDS_PER_DAY + 1);
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await withSigner(stranger, async (signer) => {
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .setPendingClaimAllowlistAdd([])
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });
    });

    describe("setPendingVaultGovernancesAdd", () => {
        describe("sets pending vault governances", () => {
            describe("when there are no repeating addresses", () => {
                it("sets", async () => {
                    await withSigner(admin, async (signer) => {
                        await protocolGovernance
                            .connect(signer)
                            .setPendingVaultGovernancesAdd([user1, user2]);

                        expect(
                            await protocolGovernance
                                .connect(signer)
                                .pendingVaultGovernancesAdd()
                        ).to.deep.equal([user1, user2]);
                    });
                });
            });

            describe("when there are repeating addresses", () => {
                it("sets", async () => {
                    await withSigner(admin, async (signer) => {
                        await protocolGovernance
                            .connect(signer)
                            .setPendingVaultGovernancesAdd([
                                user1,
                                user2,
                                user2,
                                user1,
                            ]);

                        expect(
                            await protocolGovernance
                                .connect(signer)
                                .pendingVaultGovernancesAdd()
                        ).to.deep.equal([user1, user2, user2, user1]);
                    });
                });
            });

            it("sets pendingVaultGovernancesAddTimestamp", async () => {
                await withSigner(admin, async (signer) => {
                    timestamp += timeShift;
                    sleepTo(timestamp);

                    await protocolGovernance
                        .connect(signer)
                        .setPendingVaultGovernancesAdd([user1, user2]);

                    expect(
                        Math.abs(
                            Number(
                                await protocolGovernance.pendingVaultGovernancesAddTimestamp()
                            ) - timestamp
                        )
                    ).to.be.lessThanOrEqual(SECONDS_PER_DAY + 1);
                });
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await withSigner(stranger, async (signer) => {
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .setPendingVaultGovernancesAdd([user1, user2])
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });
    });

    describe("commitVaultGovernancesAdd", () => {
        describe("when there are no repeating addresses", () => {
            it("sets vault governance add", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingVaultGovernancesAdd([user1, user2, user3]);

                    await sleep(SECONDS_PER_DAY);

                    await protocolGovernance
                        .connect(signer)
                        .commitVaultGovernancesAdd();

                    expect(
                        await protocolGovernance.isVaultGovernance(user1)
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isVaultGovernance(user2)
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isVaultGovernance(user3)
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isVaultGovernance(stranger)
                    ).to.be.equal(false);
                });
            });
        });

        describe("when there are repeating addresses", () => {
            it("sets vault governance add", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingVaultGovernancesAdd([
                            user1,
                            user2,
                            user2,
                            user1,
                            user3,
                        ]);

                    await sleep(SECONDS_PER_DAY);

                    await protocolGovernance
                        .connect(signer)
                        .commitVaultGovernancesAdd();

                    expect(
                        await protocolGovernance.isVaultGovernance(user1)
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isVaultGovernance(user2)
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isVaultGovernance(user3)
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isVaultGovernance(stranger)
                    ).to.be.equal(false);
                });
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingVaultGovernancesAdd([user1, user2]);

                    await expect(
                        protocolGovernance.commitVaultGovernancesAdd()
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });

        describe("when pendingVaultGovernancesAddTimestamp has not passed or has almost passed", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingParams(params);
                    await sleep(SECONDS_PER_DAY + 1);
                    await protocolGovernance.connect(signer).commitParams();
                    timestamp += timeShift;
                    await sleepTo(timestamp);
                    await protocolGovernance
                        .connect(signer)
                        .setPendingVaultGovernancesAdd([user1, user2]);

                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitVaultGovernancesAdd()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);

                    await sleep(1);
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitVaultGovernancesAdd()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });

        describe("when pendingVaultGovernancesAddTimestamp has not been set", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitVaultGovernancesAdd()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });
    });

    describe("commitClaimAllowlistAdd", () => {
        describe("appends zero address to list", () => {
            it("appends", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingClaimAllowlistAdd([]);

                    sleep(100 * 1000);

                    await protocolGovernance
                        .connect(signer)
                        .commitClaimAllowlistAdd();
                    expect(
                        await protocolGovernance.claimAllowlist()
                    ).to.deep.equal([]);
                });
            });
        });

        describe("appends one address to list", () => {
            it("appends", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingClaimAllowlistAdd([user1]);

                    sleep(100 * 1000);

                    await protocolGovernance
                        .connect(signer)
                        .commitClaimAllowlistAdd();
                    expect(
                        await protocolGovernance.claimAllowlist()
                    ).to.deep.equal([user1]);
                });
            });
        });

        describe("appends multiple addresses to list", () => {
            it("appends", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingClaimAllowlistAdd([deployer]);

                    sleep(100 * 1000);

                    await protocolGovernance
                        .connect(signer)
                        .commitClaimAllowlistAdd();

                    await protocolGovernance
                        .connect(signer)
                        .setPendingClaimAllowlistAdd([user1, user2]);

                    sleep(100 * 1000);

                    await protocolGovernance
                        .connect(signer)
                        .commitClaimAllowlistAdd();

                    expect(
                        await protocolGovernance
                            .connect(signer)
                            .claimAllowlist()
                    ).to.deep.equal([deployer, user1, user2]);
                });
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await withSigner(stranger, async (signer) => {
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitClaimAllowlistAdd()
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });

        describe("when does not have pre-set claim allow list add timestamp", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    timestamp += 10 ** 6;
                    sleepTo(timestamp);
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitClaimAllowlistAdd()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });

        describe("when governance delay has not passed", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    timestamp += 10 ** 6;
                    sleepTo(timestamp);
                    await protocolGovernance
                        .connect(signer)
                        .setPendingParams(paramsTimeout);

                    timestamp += 10 ** 6;
                    sleepTo(timestamp);
                    await protocolGovernance.connect(signer).commitParams();

                    await protocolGovernance
                        .connect(signer)
                        .setPendingClaimAllowlistAdd([user1, user2]);

                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitClaimAllowlistAdd()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });
    });

    describe("removeFromClaimAllowlist", async () => {
        describe("when removing non-existing address", () => {
            it("does nothing", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingClaimAllowlistAdd([user1, user2]);

                    sleep(100 * 1000);

                    await protocolGovernance
                        .connect(signer)
                        .commitClaimAllowlistAdd();
                    await protocolGovernance
                        .connect(signer)
                        .removeFromClaimAllowlist(stranger);
                    expect(
                        await protocolGovernance
                            .connect(signer)
                            .claimAllowlist()
                    ).to.deep.equal([user1, user2]);
                });
            });
        });

        describe("when remove called once", () => {
            it("removes the address", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingClaimAllowlistAdd([deployer, user1, user2]);

                    sleep(100 * 1000);

                    await protocolGovernance
                        .connect(signer)
                        .commitClaimAllowlistAdd();
                    await protocolGovernance
                        .connect(signer)
                        .removeFromClaimAllowlist(user1);
                    expect([
                        (await protocolGovernance
                            .connect(signer)
                            .isAllowedToClaim(deployer)) &&
                            (await protocolGovernance.isAllowedToClaim(user2)),
                        await protocolGovernance.isAllowedToClaim(user1),
                    ]).to.deep.equal([true, false]);
                });
            });
        });

        describe("when remove called twice", () => {
            it("removes the addresses", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingClaimAllowlistAdd([deployer, user1, user2]);
                    sleep(100 * 1000);

                    await protocolGovernance
                        .connect(signer)
                        .commitClaimAllowlistAdd();
                    await protocolGovernance
                        .connect(signer)
                        .removeFromClaimAllowlist(user1);
                    await protocolGovernance
                        .connect(signer)
                        .removeFromClaimAllowlist(user2);
                    expect([
                        await protocolGovernance.isAllowedToClaim(deployer),
                        (await protocolGovernance.isAllowedToClaim(user1)) &&
                            (await protocolGovernance.isAllowedToClaim(user2)),
                    ]).to.deep.equal([true, false]);
                });
            });
        });

        describe("when remove called twice on the same address", () => {
            it("removes the address and does not fail then", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingClaimAllowlistAdd([deployer, user1, user2]);

                    sleep(100 * 1000);

                    await protocolGovernance
                        .connect(signer)
                        .commitClaimAllowlistAdd();
                    await protocolGovernance
                        .connect(signer)
                        .removeFromClaimAllowlist(user2);
                    await protocolGovernance
                        .connect(signer)
                        .removeFromClaimAllowlist(user2);
                    expect([
                        (await protocolGovernance.isAllowedToClaim(deployer)) &&
                            (await protocolGovernance.isAllowedToClaim(user1)),
                        await protocolGovernance.isAllowedToClaim(user2),
                    ]).to.deep.equal([true, false]);
                });
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await withSigner(stranger, async (signer) => {
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .removeFromClaimAllowlist(deployer)
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });
    });

    describe("removeFromVaultGovernances", () => {
        describe("when called by not admin", () => {
            it("reverts", async () => {
                await withSigner(stranger, async (signer) => {
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .removeFromVaultGovernances(user1)
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });

        describe("when address is not in vault governances", () => {
            it("does not fail", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingVaultGovernancesAdd([user1, user2]);
                    await sleep(SECONDS_PER_DAY);
                    await protocolGovernance
                        .connect(signer)
                        .commitVaultGovernancesAdd();

                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .removeFromVaultGovernances(user3)
                    ).to.not.be.reverted;

                    expect(
                        (await protocolGovernance.vaultGovernances()).length
                    ).to.be.equal(8);
                });
            });
        });

        describe("when address is a vault governance", () => {
            describe("when attempt to remove one address", () => {
                it("removes", async () => {
                    await withSigner(admin, async (signer) => {
                        await protocolGovernance
                            .connect(signer)
                            .setPendingVaultGovernancesAdd([
                                user1,
                                user2,
                                user3,
                            ]);
                        await sleep(SECONDS_PER_DAY);
                        await protocolGovernance
                            .connect(signer)
                            .commitVaultGovernancesAdd();

                        await expect(
                            protocolGovernance
                                .connect(signer)
                                .removeFromVaultGovernances(user3)
                        ).to.not.be.reverted;
                        expect(
                            await protocolGovernance.isVaultGovernance(user3)
                        ).to.be.equal(false);
                        expect(
                            await protocolGovernance.isVaultGovernance(user2)
                        ).to.be.equal(true);
                        expect(
                            await protocolGovernance.isVaultGovernance(user1)
                        ).to.be.equal(true);
                    });
                });
            });
            describe("when attempt to remove multiple addresses", () => {
                it("removes", async () => {
                    await withSigner(admin, async (signer) => {
                        await protocolGovernance
                            .connect(signer)
                            .setPendingVaultGovernancesAdd([
                                user1,
                                user2,
                                user3,
                            ]);
                        await sleep(SECONDS_PER_DAY);
                        await protocolGovernance
                            .connect(signer)
                            .commitVaultGovernancesAdd();

                        await expect(
                            protocolGovernance
                                .connect(signer)
                                .removeFromVaultGovernances(user3)
                        ).to.not.be.reverted;
                        await expect(
                            protocolGovernance
                                .connect(signer)
                                .removeFromVaultGovernances(user2)
                        ).to.not.be.reverted;
                        await expect(
                            protocolGovernance
                                .connect(signer)
                                .removeFromVaultGovernances(user3)
                        ).to.not.be.reverted;

                        expect(
                            await protocolGovernance.isVaultGovernance(user3)
                        ).to.be.equal(false);
                        expect(
                            await protocolGovernance.isVaultGovernance(user2)
                        ).to.be.equal(false);
                        expect(
                            await protocolGovernance.isVaultGovernance(user1)
                        ).to.be.equal(true);
                    });
                });
            });
        });
    });

    describe("setPendingTokenWhitelistAdd", () => {
        it("does not allow stranger to set pending token whitelist", async () => {
            await withSigner(stranger, async (signer) => {
                await expect(
                    protocolGovernance
                        .connect(signer)
                        .setPendingTokenWhitelistAdd([])
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        it("sets pending token whitelist add and timestamp", async () => {
            await withSigner(admin, async (signer) => {
                timestamp += timeout;
                sleepTo(timestamp);
                await protocolGovernance
                    .connect(signer)
                    .setPendingTokenWhitelistAdd([
                        tokens[0].address,
                        tokens[1].address,
                    ]);
                expect(
                    await protocolGovernance
                        .connect(signer)
                        .pendingTokenWhitelistAdd()
                ).to.deep.equal([tokens[0].address, tokens[1].address]);
                expect(
                    Math.abs(
                        Number(
                            await protocolGovernance.pendingTokenWhitelistAddTimestamp()
                        ) -
                            Number(await protocolGovernance.governanceDelay()) -
                            timestamp
                    )
                ).to.be.lessThanOrEqual(10);
            });
        });
    });

    describe("commitTokenWhitelistAdd", () => {
        it("commits pending token whitelist", async () => {
            await withSigner(admin, async (signer) => {
                timestamp += timeout;
                sleepTo(timestamp);
                await protocolGovernance
                    .connect(signer)
                    .setPendingTokenWhitelistAdd([
                        tokens[0].address,
                        tokens[1].address,
                    ]);
                expect(
                    await protocolGovernance
                        .connect(signer)
                        .pendingTokenWhitelistAdd()
                ).to.deep.equal([tokens[0].address, tokens[1].address]);
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance
                    .connect(signer)
                    .commitTokenWhitelistAdd();
                expect(
                    await protocolGovernance.pendingTokenWhitelistAddTimestamp()
                ).to.be.equal(BigNumber.from(0));
                expect(await protocolGovernance.pendingTokenWhitelistAdd()).to
                    .be.empty;
            });
        });

        describe("when called noy by admin", () => {
            it("reverts", async () => {
                await withSigner(stranger, async (signer) => {
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitTokenWhitelistAdd()
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });

        describe("when setPendingTokenWhitelistAdd has not been called", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitTokenWhitelistAdd()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });

        describe("when governance delay has not passed or has almost passed", () => {
            it("reverts", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingTokenWhitelistAdd([
                            tokens[0].address,
                            tokens[1].address,
                        ]);
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitTokenWhitelistAdd()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    await sleep(
                        Number(await protocolGovernance.governanceDelay()) - 5
                    );
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .commitTokenWhitelistAdd()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });

        describe("when setting to identic addresses", () => {
            it("passes", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingTokenWhitelistAdd([
                            tokens[0].address,
                            tokens[1].address,
                            tokens[0].address,
                        ]);
                    await sleep(
                        Number(await protocolGovernance.governanceDelay())
                    );
                    await protocolGovernance
                        .connect(signer)
                        .commitTokenWhitelistAdd();
                    expect(
                        await protocolGovernance.tokenWhitelist()
                    ).to.deep.equal([
                        wbtc,
                        usdc,
                        weth,
                        tokens[0].address,
                        tokens[1].address,
                    ]);
                });
            });
        });
    });

    describe("removeFromTokenWhitelist", () => {
        describe("when called not by admin", () => {
            it("reverts", async () => {
                await withSigner(stranger, async (signer) => {
                    await expect(
                        protocolGovernance
                            .connect(signer)
                            .removeFromTokenWhitelist(tokens[0].address)
                    ).to.be.revertedWith(Exceptions.ADMIN);
                });
            });
        });

        describe("when passed an address which is not in token whitelist", () => {
            it("passes", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingTokenWhitelistAdd([
                            tokens[0].address,
                            tokens[1].address,
                        ]);
                    await sleep(
                        Number(await protocolGovernance.governanceDelay())
                    );
                    await protocolGovernance
                        .connect(signer)
                        .commitTokenWhitelistAdd();
                    await protocolGovernance
                        .connect(signer)
                        .removeFromTokenWhitelist(tokens[2].address);
                    expect(
                        await protocolGovernance.isAllowedToken(
                            tokens[1].address
                        )
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isAllowedToken(
                            tokens[0].address
                        )
                    ).to.be.equal(true);
                });
            });
        });

        it("removes", async () => {
            await withSigner(admin, async (signer) => {
                await protocolGovernance
                    .connect(signer)
                    .setPendingTokenWhitelistAdd([
                        tokens[0].address,
                        tokens[1].address,
                    ]);
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance
                    .connect(signer)
                    .commitTokenWhitelistAdd();
                await protocolGovernance
                    .connect(signer)
                    .removeFromTokenWhitelist(tokens[0].address);
                expect(
                    await protocolGovernance.isAllowedToken(tokens[1].address)
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isAllowedToken(tokens[0].address)
                ).to.be.equal(false);
                expect(await protocolGovernance.tokenWhitelist()).to.deep.equal(
                    [wbtc, usdc, weth, tokens[1].address]
                );
            });
        });

        describe("when call commit on removed token", () => {
            it("passes", async () => {
                await withSigner(admin, async (signer) => {
                    await protocolGovernance
                        .connect(signer)
                        .setPendingTokenWhitelistAdd([
                            tokens[0].address,
                            tokens[1].address,
                        ]);
                    await sleep(
                        Number(await protocolGovernance.governanceDelay())
                    );
                    await protocolGovernance
                        .connect(signer)
                        .commitTokenWhitelistAdd();
                    await protocolGovernance
                        .connect(signer)
                        .removeFromTokenWhitelist(tokens[0].address);
                    await protocolGovernance
                        .connect(signer)
                        .setPendingTokenWhitelistAdd([
                            tokens[0].address,
                            tokens[1].address,
                        ]);
                    await sleep(
                        Number(await protocolGovernance.governanceDelay())
                    );
                    await protocolGovernance
                        .connect(signer)
                        .commitTokenWhitelistAdd();
                    expect(
                        await protocolGovernance.isAllowedToken(
                            tokens[1].address
                        )
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isAllowedToken(
                            tokens[0].address
                        )
                    ).to.be.equal(true);
                });
            });
        });
    });
});
