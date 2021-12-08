import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { Contract, Signer } from "ethers";
import { BigNumber } from "@ethersproject/bignumber";
import Exceptions from "./library/Exceptions";
import { ParamsStruct, ProtocolGovernance } from "./types/ProtocolGovernance";
import { deployERC20Tokens } from "./library/Deployments";
import {
    now,
    sleep,
    sleepTo,
    toObject,
    addSigner,
    removeSigner,
} from "./library/Helpers";
import { VaultRegistry } from "./types";

describe("ProtocolGovernance", () => {
    const SECONDS_PER_DAY = 60 * 60 * 24;

    let protocolGovernance: ProtocolGovernance;
    let vaultRegistry: VaultRegistry;
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let stranger1: string;
    let stranger2: string;
    let stranger3: string;
    let treasury: string;
    let timestamp: number;
    let timeout: number;
    let timeShift: number;
    let params: ParamsStruct;
    let paramsZero: ParamsStruct;
    let paramsTimeout: ParamsStruct;
    let paramsEmpty: ParamsStruct;
    let paramsDefault: ParamsStruct;
    let deploymentFixture: Function;
    let tokens: Contract[];
    let wbtc: string;
    let weth: string;
    let usdc: string;

    before(async () => {
        timeout = SECONDS_PER_DAY / 2;
        timeShift = 10 ** 10;
        timestamp = now() + timeShift;

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            const {
                deployer: d,
                admin: a,
                stranger: s,
                stranger1: s1,
                stranger2: s2,
                stranger3: s3,
                treasury: t,
                weth: we,
                wbtc: wb,
                usdc: us,
            } = await getNamedAccounts();
            [treasury, stranger1, stranger2, stranger3, wbtc, weth, usdc] = [
                t,
                s1,
                s2,
                s3,
                wb,
                we,
                us,
            ];

            deployer = await addSigner(d);
            admin = await addSigner(a);
            stranger = await addSigner(s);

            protocolGovernance = await ethers.getContract("ProtocolGovernance");
            vaultRegistry = await ethers.getContract("VaultRegistry");

            params = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(10),
                governanceDelay: BigNumber.from(100),
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

    after(async () => {
        await removeSigner(await deployer.getAddress());
        await removeSigner(await admin.getAddress());
        await removeSigner(await stranger.getAddress());
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
                await protocolGovernance.connect(admin).setPendingParams({
                    permissionless: true,
                    maxTokensPerVault: BigNumber.from(10),
                    governanceDelay: BigNumber.from(SECONDS_PER_DAY * 10),
                    protocolTreasury: treasury,
                });
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance.connect(admin).commitParams();
                await expect(
                    protocolGovernance.connect(admin).setPendingParams(params)
                ).to.be.revertedWith(Exceptions.MAX_GOVERNANCE_DELAY);
            });
        });
        describe("when called once", () => {
            it("sets the params", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingParams(params);
                expect(
                    toObject(await protocolGovernance.functions.pendingParams())
                ).to.deep.equal(params);
            });
        });

        describe("when called twice", () => {
            it("sets the params", async () => {
                paramsZero = {
                    permissionless: false,
                    maxTokensPerVault: BigNumber.from(10),
                    governanceDelay: BigNumber.from(0),
                    protocolTreasury: treasury,
                };
                paramsTimeout = {
                    permissionless: false,
                    maxTokensPerVault: BigNumber.from(10),
                    governanceDelay: BigNumber.from(timeout),
                    protocolTreasury: treasury,
                };
                await protocolGovernance
                    .connect(admin)
                    .setPendingParams(paramsTimeout);
                await protocolGovernance
                    .connect(admin)
                    .setPendingParams(paramsZero);

                expect(
                    toObject(await protocolGovernance.functions.pendingParams())
                ).to.deep.equal(paramsZero);
            });
        });

        describe("when called by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .setPendingParams(params)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    it("sets governance delay", async () => {
        timestamp += timeShift;
        await sleepTo(timestamp);
        await protocolGovernance.connect(admin).setPendingParams(params);
        expect(
            Math.abs(
                Number(
                    await protocolGovernance
                        .connect(admin)
                        .pendingParamsTimestamp()
                ) -
                    timestamp -
                    Number(
                        await protocolGovernance
                            .connect(admin)
                            .governanceDelay()
                    )
            )
        ).to.be.lessThanOrEqual(10);
    });

    describe("commitParams", () => {
        paramsZero = {
            permissionless: false,
            maxTokensPerVault: BigNumber.from(1),
            governanceDelay: BigNumber.from(0),
            protocolTreasury: treasury,
        };

        paramsTimeout = {
            permissionless: true,
            maxTokensPerVault: BigNumber.from(1),
            governanceDelay: BigNumber.from(SECONDS_PER_DAY),
            protocolTreasury: treasury,
        };

        paramsDefault = {
            permissionless: false,
            maxTokensPerVault: BigNumber.from(0),
            governanceDelay: BigNumber.from(0),
            protocolTreasury: ethers.constants.AddressZero,
        };

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingParams(paramsZero);

                await expect(
                    protocolGovernance.connect(stranger).commitParams()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when governance delay has not passed", () => {
            describe("when call immediately", () => {
                it("reverts", async () => {
                    await protocolGovernance
                        .connect(admin)
                        .setPendingParams(paramsTimeout);

                    await sleep(
                        Number(await protocolGovernance.governanceDelay())
                    );

                    await protocolGovernance.connect(admin).commitParams();

                    await protocolGovernance
                        .connect(admin)
                        .setPendingParams(paramsZero);
                    await expect(
                        protocolGovernance.connect(admin).commitParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });

            describe("when delay has almost passed", () => {
                it("reverts", async () => {
                    await protocolGovernance
                        .connect(admin)
                        .setPendingParams(paramsTimeout);

                    await sleep(
                        Number(await protocolGovernance.governanceDelay())
                    );

                    await protocolGovernance.connect(admin).commitParams();

                    await sleep(
                        Number(await protocolGovernance.governanceDelay()) - 2
                    );

                    await protocolGovernance
                        .connect(admin)
                        .setPendingParams(paramsZero);
                    await expect(
                        protocolGovernance.connect(admin).commitParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });

        describe("when governanceDelay is 0 and maxTokensPerVault is 0", () => {
            it("reverts", async () => {
                paramsEmpty = {
                    permissionless: true,
                    maxTokensPerVault: BigNumber.from(0),
                    governanceDelay: BigNumber.from(0),
                    protocolTreasury: treasury,
                };

                await protocolGovernance
                    .connect(admin)
                    .setPendingParams(paramsEmpty);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await expect(
                    protocolGovernance.connect(admin).commitParams()
                ).to.be.revertedWith(Exceptions.EMPTY_PARAMS);
            });
        });

        it("commits params", async () => {
            await protocolGovernance
                .connect(admin)
                .setPendingParams(paramsZero);

            await sleep(Number(await protocolGovernance.governanceDelay()));

            await protocolGovernance.connect(admin).commitParams();
            expect(toObject(await protocolGovernance.params())).to.deep.equal(
                paramsZero
            );
        });

        it("deletes pending params", async () => {
            await protocolGovernance
                .connect(admin)
                .setPendingParams(paramsZero);

            await sleep(Number(await protocolGovernance.governanceDelay()));

            await protocolGovernance.connect(admin).commitParams();
            expect(
                toObject(
                    await protocolGovernance.connect(admin).pendingParams()
                )
            ).to.deep.equal(paramsDefault);
        });

        describe("when commited twice", () => {
            it("reverts", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingParams(paramsZero);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance.connect(admin).commitParams();

                await expect(
                    protocolGovernance.connect(admin).commitParams()
                ).to.be.revertedWith(Exceptions.EMPTY_PARAMS);
            });
        });

        it("deletes pending params timestamp", async () => {
            await protocolGovernance
                .connect(admin)
                .setPendingParams(paramsTimeout);

            await sleep(Number(await protocolGovernance.governanceDelay()));
            await protocolGovernance.connect(admin).commitParams();

            expect(
                await protocolGovernance.connect(admin).pendingParamsTimestamp()
            ).to.be.equal(BigNumber.from(0));
        });
    });

    describe("setPendingClaimAllowlistAdd", () => {
        paramsZero = {
            permissionless: false,
            maxTokensPerVault: BigNumber.from(1),
            governanceDelay: BigNumber.from(0),
            protocolTreasury: treasury,
        };

        paramsTimeout = {
            permissionless: true,
            maxTokensPerVault: BigNumber.from(1),
            governanceDelay: BigNumber.from(SECONDS_PER_DAY),
            protocolTreasury: treasury,
        };

        it("sets pending list", async () => {
            await protocolGovernance
                .connect(admin)
                .setPendingClaimAllowlistAdd([stranger1, stranger2]);

            expect(
                await protocolGovernance
                    .connect(admin)
                    .pendingClaimAllowlistAdd()
            ).to.deep.equal([stranger1, stranger2]);
        });

        it("sets correct pending timestamp with zero gonernance delay", async () => {
            timestamp += 10 ** 6;
            await sleepTo(timestamp);
            await protocolGovernance
                .connect(admin)
                .setPendingParams(paramsZero);

            timestamp += 10 ** 6;
            await sleepTo(timestamp);
            await protocolGovernance.connect(admin).commitParams();

            await protocolGovernance
                .connect(admin)
                .setPendingClaimAllowlistAdd([stranger1, stranger2]);

            expect(
                Math.abs(
                    Number(
                        await protocolGovernance
                            .connect(admin)
                            .pendingClaimAllowlistAddTimestamp()
                    ) - timestamp
                )
            ).to.be.lessThanOrEqual(SECONDS_PER_DAY + 1);
        });

        it("sets correct pending timestamp with non-zero governance delay", async () => {
            timestamp += 10 ** 6;
            await sleepTo(timestamp);
            await protocolGovernance
                .connect(admin)
                .setPendingParams(paramsTimeout);

            timestamp += 10 ** 6;
            await sleepTo(timestamp);
            await protocolGovernance.connect(admin).commitParams();

            await protocolGovernance
                .connect(admin)
                .setPendingClaimAllowlistAdd([stranger1, stranger2]);

            expect(
                Math.abs(
                    Number(
                        await protocolGovernance.pendingClaimAllowlistAddTimestamp()
                    ) -
                        (timestamp + timeout)
                )
            ).to.be.lessThanOrEqual(SECONDS_PER_DAY + 1);
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
                    await protocolGovernance
                        .connect(admin)
                        .setPendingVaultGovernancesAdd([stranger1, stranger2]);

                    expect(
                        await protocolGovernance
                            .connect(admin)
                            .pendingVaultGovernancesAdd()
                    ).to.deep.equal([stranger1, stranger2]);
                });
            });

            describe("when there are repeating addresses", () => {
                it("sets", async () => {
                    await protocolGovernance
                        .connect(admin)
                        .setPendingVaultGovernancesAdd([
                            stranger1,
                            stranger2,
                            stranger2,
                            stranger1,
                        ]);

                    expect(
                        await protocolGovernance
                            .connect(admin)
                            .pendingVaultGovernancesAdd()
                    ).to.deep.equal([
                        stranger1,
                        stranger2,
                        stranger2,
                        stranger1,
                    ]);
                });
            });

            it("sets pendingVaultGovernancesAddTimestamp", async () => {
                timestamp += timeShift;
                await sleepTo(timestamp);

                await protocolGovernance
                    .connect(admin)
                    .setPendingVaultGovernancesAdd([stranger1, stranger2]);

                expect(
                    Math.abs(
                        Number(
                            await protocolGovernance.pendingVaultGovernancesAddTimestamp()
                        ) - timestamp
                    )
                ).to.be.lessThanOrEqual(SECONDS_PER_DAY + 1);
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .setPendingVaultGovernancesAdd([stranger1, stranger2])
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("commitVaultGovernancesAdd", () => {
        describe("when there are no repeating addresses", () => {
            it("sets vault governance add", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingVaultGovernancesAdd([
                        stranger1,
                        stranger2,
                        stranger3,
                    ]);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitVaultGovernancesAdd();

                expect(
                    await protocolGovernance.isVaultGovernance(stranger1)
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(stranger2)
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(stranger3)
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
                await protocolGovernance
                    .connect(admin)
                    .setPendingVaultGovernancesAdd([
                        stranger1,
                        stranger2,
                        stranger2,
                        stranger1,
                        stranger3,
                    ]);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitVaultGovernancesAdd();

                expect(
                    await protocolGovernance.isVaultGovernance(stranger1)
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(stranger2)
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isVaultGovernance(stranger3)
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
                await protocolGovernance
                    .connect(admin)
                    .setPendingVaultGovernancesAdd([stranger1, stranger2]);

                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .commitVaultGovernancesAdd()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when pendingVaultGovernancesAddTimestamp has not passed or has almost passed", () => {
            it("reverts", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingParams(params);
                await sleep(
                    Number(await protocolGovernance.governanceDelay()) + 1
                );

                await protocolGovernance.connect(admin).commitParams();
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance
                    .connect(admin)
                    .setPendingVaultGovernancesAdd([stranger1, stranger2]);

                await expect(
                    protocolGovernance
                        .connect(admin)
                        .commitVaultGovernancesAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);

                await sleep(1);
                await expect(
                    protocolGovernance
                        .connect(admin)
                        .commitVaultGovernancesAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });

        describe("when pendingVaultGovernancesAddTimestamp has not been set", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(admin)
                        .commitVaultGovernancesAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });
    });

    describe("commitClaimAllowlistAdd", () => {
        paramsTimeout = {
            permissionless: true,
            maxTokensPerVault: BigNumber.from(1),
            governanceDelay: BigNumber.from(SECONDS_PER_DAY),
            protocolTreasury: treasury,
        };

        describe("appends zero address to list", () => {
            it("appends", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingClaimAllowlistAdd([]);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitClaimAllowlistAdd();
                expect(await protocolGovernance.claimAllowlist()).to.deep.equal(
                    []
                );
            });
        });

        describe("appends one address to list", () => {
            it("appends", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingClaimAllowlistAdd([stranger1]);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitClaimAllowlistAdd();
                expect(await protocolGovernance.claimAllowlist()).to.deep.equal(
                    [stranger1]
                );
            });
        });

        describe("appends multiple addresses to list", () => {
            it("appends", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingClaimAllowlistAdd([await deployer.getAddress()]);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitClaimAllowlistAdd();

                await protocolGovernance
                    .connect(admin)
                    .setPendingClaimAllowlistAdd([stranger1, stranger2]);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitClaimAllowlistAdd();

                expect(await protocolGovernance.claimAllowlist()).to.deep.equal(
                    [await deployer.getAddress(), stranger1, stranger2]
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
                await expect(
                    protocolGovernance.connect(admin).commitClaimAllowlistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });

        describe("when governance delay has not passed", () => {
            it("reverts", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingParams(paramsTimeout);

                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance.connect(admin).commitParams();

                await protocolGovernance
                    .connect(admin)
                    .setPendingClaimAllowlistAdd([stranger1, stranger2]);

                await expect(
                    protocolGovernance.connect(admin).commitClaimAllowlistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });
    });

    describe("removeFromClaimAllowlist", async () => {
        describe("when removing non-existing address", () => {
            it("does nothing", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingClaimAllowlistAdd([stranger1, stranger2]);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitClaimAllowlistAdd();
                await protocolGovernance
                    .connect(admin)
                    .removeFromClaimAllowlist(await stranger.getAddress());
                expect(await protocolGovernance.claimAllowlist()).to.deep.equal(
                    [stranger1, stranger2]
                );
            });
        });

        describe("when remove called once", () => {
            it("removes the address", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingClaimAllowlistAdd([
                        await deployer.getAddress(),
                        stranger1,
                        stranger2,
                    ]);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitClaimAllowlistAdd();
                await protocolGovernance
                    .connect(admin)
                    .removeFromClaimAllowlist(stranger1);
                expect([
                    (await protocolGovernance.isAllowedToClaim(
                        await deployer.getAddress()
                    )) &&
                        (await protocolGovernance.isAllowedToClaim(stranger2)),
                    await protocolGovernance.isAllowedToClaim(stranger1),
                ]).to.deep.equal([true, false]);
            });
        });

        describe("when remove called twice", () => {
            it("removes the addresses", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingClaimAllowlistAdd([
                        await deployer.getAddress(),
                        stranger1,
                        stranger2,
                    ]);
                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitClaimAllowlistAdd();
                await protocolGovernance
                    .connect(admin)
                    .removeFromClaimAllowlist(stranger1);
                await protocolGovernance
                    .connect(admin)
                    .removeFromClaimAllowlist(stranger2);
                expect([
                    await protocolGovernance.isAllowedToClaim(
                        await deployer.getAddress()
                    ),
                    (await protocolGovernance.isAllowedToClaim(stranger1)) &&
                        (await protocolGovernance.isAllowedToClaim(stranger2)),
                ]).to.deep.equal([true, false]);
            });
        });

        describe("when remove called twice on the same address", () => {
            it("removes the address and does not fail then", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingClaimAllowlistAdd([
                        await deployer.getAddress(),
                        stranger1,
                        stranger2,
                    ]);

                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitClaimAllowlistAdd();
                await protocolGovernance
                    .connect(admin)
                    .removeFromClaimAllowlist(stranger2);
                await protocolGovernance
                    .connect(admin)
                    .removeFromClaimAllowlist(stranger2);
                expect([
                    (await protocolGovernance.isAllowedToClaim(
                        await deployer.getAddress()
                    )) &&
                        (await protocolGovernance.isAllowedToClaim(stranger1)),
                    await protocolGovernance.isAllowedToClaim(stranger2),
                ]).to.deep.equal([true, false]);
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .removeFromClaimAllowlist(await deployer.getAddress())
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
                        .removeFromVaultGovernances(stranger1)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when address is not in vault governances", () => {
            it("does not fail", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingVaultGovernancesAdd([stranger1, stranger2]);
                await sleep(Number(await protocolGovernance.governanceDelay()));

                await protocolGovernance
                    .connect(admin)
                    .commitVaultGovernancesAdd();

                await expect(
                    protocolGovernance
                        .connect(admin)
                        .removeFromVaultGovernances(stranger3)
                ).to.not.be.reverted;

                expect(
                    (await protocolGovernance.vaultGovernances()).length
                ).to.be.equal(8);
            });
        });

        describe("when address is a vault governance", () => {
            describe("when attempt to remove one address", () => {
                it("removes", async () => {
                    await protocolGovernance
                        .connect(admin)
                        .setPendingVaultGovernancesAdd([
                            stranger1,
                            stranger2,
                            stranger3,
                        ]);
                    await sleep(
                        Number(await protocolGovernance.governanceDelay())
                    );

                    await protocolGovernance
                        .connect(admin)
                        .commitVaultGovernancesAdd();

                    await expect(
                        protocolGovernance
                            .connect(admin)
                            .removeFromVaultGovernances(stranger3)
                    ).to.not.be.reverted;
                    expect(
                        await protocolGovernance.isVaultGovernance(stranger3)
                    ).to.be.equal(false);
                    expect(
                        await protocolGovernance.isVaultGovernance(stranger2)
                    ).to.be.equal(true);
                    expect(
                        await protocolGovernance.isVaultGovernance(stranger1)
                    ).to.be.equal(true);
                });
            });
            describe("when attempt to remove multiple addresses", () => {
                it("removes", async () => {
                    await protocolGovernance
                        .connect(admin)
                        .setPendingVaultGovernancesAdd([
                            stranger1,
                            stranger2,
                            stranger3,
                        ]);
                    await sleep(
                        Number(await protocolGovernance.governanceDelay())
                    );

                    await protocolGovernance
                        .connect(admin)
                        .commitVaultGovernancesAdd();

                    await expect(
                        protocolGovernance
                            .connect(admin)
                            .removeFromVaultGovernances(stranger3)
                    ).to.not.be.reverted;
                    await expect(
                        protocolGovernance
                            .connect(admin)
                            .removeFromVaultGovernances(stranger2)
                    ).to.not.be.reverted;
                    await expect(
                        protocolGovernance
                            .connect(admin)
                            .removeFromVaultGovernances(stranger3)
                    ).to.not.be.reverted;

                    expect(
                        await protocolGovernance.isVaultGovernance(stranger3)
                    ).to.be.equal(false);
                    expect(
                        await protocolGovernance.isVaultGovernance(stranger2)
                    ).to.be.equal(false);
                    expect(
                        await protocolGovernance.isVaultGovernance(stranger1)
                    ).to.be.equal(true);
                });
            });
        });
    });

    describe("setPendingTokenWhitelistAdd", () => {
        it("does not allow stranger to set pending token whitelist", async () => {
            await expect(
                protocolGovernance
                    .connect(stranger)
                    .setPendingTokenWhitelistAdd([])
            ).to.be.revertedWith(Exceptions.ADMIN);
        });

        it("sets pending token whitelist add and timestamp", async () => {
            timestamp += timeout;
            await sleepTo(timestamp);
            await protocolGovernance
                .connect(admin)
                .setPendingTokenWhitelistAdd([
                    tokens[0].address,
                    tokens[1].address,
                ]);
            expect(
                await protocolGovernance
                    .connect(admin)
                    .pendingTokenWhitelistAdd()
            ).to.deep.equal([tokens[0].address, tokens[1].address]);
            expect(
                Math.abs(
                    Number(
                        await protocolGovernance
                            .connect(admin)
                            .pendingTokenWhitelistAddTimestamp()
                    ) -
                        Number(await protocolGovernance.governanceDelay()) -
                        timestamp
                )
            ).to.be.lessThanOrEqual(10);
        });
    });

    describe("commitTokenWhitelistAdd", () => {
        it("commits pending token whitelist", async () => {
            await protocolGovernance
                .connect(admin)
                .setPendingTokenWhitelistAdd([
                    tokens[0].address,
                    tokens[1].address,
                ]);
            expect(
                await protocolGovernance
                    .connect(admin)
                    .pendingTokenWhitelistAdd()
            ).to.deep.equal([tokens[0].address, tokens[1].address]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await protocolGovernance.connect(admin).commitTokenWhitelistAdd();
            expect(
                await protocolGovernance.pendingTokenWhitelistAddTimestamp()
            ).to.be.equal(BigNumber.from(0));
            expect(await protocolGovernance.pendingTokenWhitelistAdd()).to.be
                .empty;
        });

        describe("when called noy by admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .commitTokenWhitelistAdd()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when setPendingTokenWhitelistAdd has not been called", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance.connect(admin).commitTokenWhitelistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });

        describe("when governance delay has not passed or has almost passed", () => {
            it("reverts", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingTokenWhitelistAdd([
                        tokens[0].address,
                        tokens[1].address,
                    ]);
                await expect(
                    protocolGovernance.connect(admin).commitTokenWhitelistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
                await sleep(
                    Number(await protocolGovernance.governanceDelay()) - 5
                );
                await expect(
                    protocolGovernance.connect(admin).commitTokenWhitelistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });

        describe("when setting to identic addresses", () => {
            it("passes", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingTokenWhitelistAdd([
                        tokens[0].address,
                        tokens[1].address,
                        tokens[0].address,
                    ]);
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance
                    .connect(admin)
                    .commitTokenWhitelistAdd();
                expect(await protocolGovernance.tokenWhitelist()).to.deep.equal(
                    [wbtc, usdc, weth, tokens[0].address, tokens[1].address]
                );
            });
        });
    });

    describe("removeFromTokenWhitelist", () => {
        describe("when called not by admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance
                        .connect(stranger)
                        .removeFromTokenWhitelist(tokens[0].address)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when passed an address which is not in token whitelist", () => {
            it("passes", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingTokenWhitelistAdd([
                        tokens[0].address,
                        tokens[1].address,
                    ]);
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance
                    .connect(admin)
                    .commitTokenWhitelistAdd();
                await protocolGovernance
                    .connect(admin)
                    .removeFromTokenWhitelist(tokens[2].address);
                expect(
                    await protocolGovernance.isAllowedToken(tokens[1].address)
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isAllowedToken(tokens[0].address)
                ).to.be.equal(true);
            });
        });

        it("removes", async () => {
            await protocolGovernance
                .connect(admin)
                .setPendingTokenWhitelistAdd([
                    tokens[0].address,
                    tokens[1].address,
                ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await protocolGovernance.connect(admin).commitTokenWhitelistAdd();
            await protocolGovernance
                .connect(admin)
                .removeFromTokenWhitelist(tokens[0].address);
            expect(
                await protocolGovernance.isAllowedToken(tokens[1].address)
            ).to.be.equal(true);
            expect(
                await protocolGovernance.isAllowedToken(tokens[0].address)
            ).to.be.equal(false);
            expect(
                await protocolGovernance.connect(admin).tokenWhitelist()
            ).to.deep.equal([wbtc, usdc, weth, tokens[1].address]);
        });

        describe("when call commit on removed token", () => {
            it("passes", async () => {
                await protocolGovernance
                    .connect(admin)
                    .setPendingTokenWhitelistAdd([
                        tokens[0].address,
                        tokens[1].address,
                    ]);
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance
                    .connect(admin)
                    .commitTokenWhitelistAdd();
                await protocolGovernance
                    .connect(admin)
                    .removeFromTokenWhitelist(tokens[0].address);
                await protocolGovernance
                    .connect(admin)
                    .setPendingTokenWhitelistAdd([
                        tokens[0].address,
                        tokens[1].address,
                    ]);
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance
                    .connect(admin)
                    .commitTokenWhitelistAdd();
                expect(
                    await protocolGovernance.isAllowedToken(tokens[1].address)
                ).to.be.equal(true);
                expect(
                    await protocolGovernance.isAllowedToken(tokens[0].address)
                ).to.be.equal(true);
            });
        });
    });
});
