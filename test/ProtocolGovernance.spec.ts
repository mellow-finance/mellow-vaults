import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    generateSingleParams,
    now,
    randomAddress,
    sleep,
    sleepTo,
    toObject,
    withSigner,
} from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import { contract } from "./library/setup";
import { ParamsStruct, IProtocolGovernance } from "./types/IProtocolGovernance";
import { address, uint8, uint256, pit, RUNS } from "./library/property";
import { Arbitrary, tuple, integer, Random } from "fast-check";
import { BigNumber } from "ethers";
import {
    PROTOCOL_GOVERNANCE_INTERFACE_ID,
    VAULT_INTERFACE_ID,
} from "./library/Constants";
import assert from "assert";

const MAX_GOVERNANCE_DELAY = BigNumber.from(60 * 60 * 24 * 7);

type CustomContext = {};
type DeployOptions = {};

function maskByPermissionIds(permissionIds: BigNumber[]): BigNumber {
    let mask = BigNumber.from(0);
    for (let i = 0; i < permissionIds.length; i++) {
        mask = mask.or(BigNumber.from(1).shl(Number(permissionIds[i])));
    }
    return mask;
}

const paramsArb: Arbitrary<ParamsStruct> = tuple(
    integer({ min: 1, max: 100 }),
    integer({ min: 1, max: 86400 }),
    address.filter((x) => x !== ethers.constants.AddressZero),
    uint256,
    uint256.filter((x) => x.gt(200_000))
).map(
    ([
        maxTokensPerVault,
        governanceDelay,
        protocolTreasury,
        forceAllowMask,
        withdrawLimit,
    ]) => ({
        maxTokensPerVault: BigNumber.from(maxTokensPerVault),
        governanceDelay: BigNumber.from(governanceDelay),
        protocolTreasury: protocolTreasury,
        forceAllowMask: BigNumber.from(forceAllowMask),
        withdrawLimit: BigNumber.from(withdrawLimit),
    })
);

const emptyParams: ParamsStruct = {
    maxTokensPerVault: BigNumber.from(0),
    governanceDelay: BigNumber.from(0),
    protocolTreasury: ethers.constants.AddressZero,
    forceAllowMask: BigNumber.from(0),
    withdrawLimit: BigNumber.from(0),
};

contract<IProtocolGovernance, CustomContext, DeployOptions>(
    "ProtocolGovernance",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { address } = await deployments.get(
                        "ProtocolGovernance"
                    );
                    this.subject = await ethers.getContractAt(
                        "ProtocolGovernance",
                        address
                    );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
            this.startTimestamp = now();
            await sleepTo(this.startTimestamp);
        });

        describe("#stagedPermissionGrantsTimestamps", () => {
            describe("properties", () => {
                pit(
                    `timestamp equals #stagePermissionGrants's block.timestamp + governanceDelay`,
                    { numRuns: 1 },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        const governanceDelay: BigNumber =
                            await this.subject.governanceDelay();
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        expect(
                            await this.subject.stagedPermissionGrantsTimestamps(
                                target
                            )
                        ).to.eql(
                            governanceDelay.add(this.startTimestamp).add(1)
                        );
                        return true;
                    }
                );
                pit(
                    `timestamp updates when #stagePermissionGrants is called twice`,
                    { numRuns: 1 },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8.filter((x) => x.lt(250)),
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        const perviousTimestamp: BigNumber =
                            await this.subject.stagedPermissionGrantsTimestamps(
                                target
                            );
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [
                                permissionId.add(1),
                            ]);
                        expect(
                            await this.subject.stagedPermissionGrantsTimestamps(
                                target
                            )
                        ).to.be.gt(perviousTimestamp);
                        return true;
                    }
                );
                pit(
                    `returns zero on unknown address`,
                    { numRuns: RUNS.verylow },
                    address,
                    async (target: string) => {
                        expect(
                            await this.subject.stagedPermissionGrantsTimestamps(
                                target
                            )
                        ).to.deep.equal(BigNumber.from(0));
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stagedPermissionGrantsTimestamps(
                                    randomAddress()
                                )
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#stagedPermissionGrantsMasks", () => {
            describe("properties", () => {
                pit(
                    `updates when #stagePermissionGrants is called`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        expect(
                            await this.subject.stagedPermissionGrantsMasks(
                                target
                            )
                        ).to.deep.equal(maskByPermissionIds([permissionId]));
                        return true;
                    }
                );
                pit(
                    `is not affected by #revokePermissions`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await this.subject
                            .connect(this.admin)
                            .revokePermissions(target, [permissionId]);
                        expect(
                            await this.subject.stagedPermissionGrantsMasks(
                                target
                            )
                        ).to.deep.equal(maskByPermissionIds([permissionId]));
                        return true;
                    }
                );
                pit(
                    `clears when #rollbackAllPermissionGrants is called`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await this.subject
                            .connect(this.admin)
                            .rollbackAllPermissionGrants();
                        expect(
                            await this.subject.stagedPermissionGrantsMasks(
                                target
                            )
                        ).to.deep.equal(BigNumber.from(0));
                        return true;
                    }
                );
                pit(
                    `returns zero on unknown address`,
                    { numRuns: RUNS.verylow },
                    address,
                    async (target: string) => {
                        expect(
                            await this.subject.stagedPermissionGrantsTimestamps(
                                target
                            )
                        ).to.deep.equal(BigNumber.from(0));
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stagedPermissionGrantsMasks(randomAddress())
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#permissionMasks", () => {
            describe("properties", () => {
                pit(
                    `is not affected by #stagePermissionGrants`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        expect(
                            await this.subject.permissionMasks(target)
                        ).to.deep.equal(BigNumber.from(0));
                        return true;
                    }
                );
                pit(
                    `is not affected by #rollbackAllPermissionGrants`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        await this.subject
                            .connect(this.admin)
                            .rollbackAllPermissionGrants();
                        expect(
                            await this.subject.permissionMasks(target)
                        ).to.deep.equal(maskByPermissionIds([permissionId]));
                        return true;
                    }
                );
                pit(
                    `updates by #stagePermissionGrants + #commitPermissionGrantes`,
                    { numRuns: 1 },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        expect(
                            await this.subject.permissionMasks(target)
                        ).to.deep.equal(maskByPermissionIds([permissionId]));
                        return true;
                    }
                );
                pit(
                    `returns zero on a random address`,
                    { numRuns: RUNS.verylow },
                    address,
                    async (target: string) => {
                        expect(
                            await this.subject.permissionMasks(target)
                        ).to.deep.equal(BigNumber.from(0));
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .permissionMasks(randomAddress())
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#stagedParamsTimestamp", () => {
            pit(
                `timestamp equals #stageParams's block.timestamp + governanceDelay`,
                { numRuns: 1 },
                paramsArb,
                async (params: ParamsStruct) => {
                    const governanceDelay: BigNumber =
                        await this.subject.governanceDelay();
                    await this.subject.connect(this.admin).stageParams(params);
                    expect(await this.subject.stagedParamsTimestamp()).to.eql(
                        governanceDelay.add(this.startTimestamp).add(1)
                    );
                    return true;
                }
            );
            pit(
                `clears by #commitParams`,
                { numRuns: RUNS.verylow },
                paramsArb,
                async (params: ParamsStruct) => {
                    await this.subject.connect(this.admin).stageParams(params);
                    await sleep(await this.subject.governanceDelay());
                    await this.subject.connect(this.admin).commitParams();
                    expect(
                        await this.subject.stagedParamsTimestamp()
                    ).to.deep.equal(BigNumber.from(0));
                    return true;
                }
            );

            describe("edge cases", () => {
                describe("when nothing is set", () => {
                    it("returns zero", async () => {
                        expect(
                            await this.subject.stagedParamsTimestamp()
                        ).to.deep.equal(BigNumber.from(0));
                    });
                });
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).stagedParamsTimestamp()
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#stagedParams", () => {
            describe("properties", () => {
                pit(
                    `updates by #stageParams`,
                    { numRuns: RUNS.verylow },
                    paramsArb,
                    async (params: ParamsStruct) => {
                        await this.subject
                            .connect(this.admin)
                            .stageParams(params);
                        expect(
                            toObject(await this.subject.stagedParams())
                        ).to.equivalent(params);
                        return true;
                    }
                );
                pit(
                    `clears by #commitParams`,
                    { numRuns: RUNS.verylow },
                    paramsArb,
                    async (params: ParamsStruct) => {
                        await this.subject
                            .connect(this.admin)
                            .stageParams(params);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject.connect(this.admin).commitParams();
                        expect(
                            toObject(await this.subject.stagedParams())
                        ).to.equivalent(emptyParams);
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).stagedParams()
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#params", () => {
            describe("properties", () => {
                pit(
                    `is not affected by #stageParams`,
                    { numRuns: RUNS.low },
                    paramsArb,
                    async (params: ParamsStruct) => {
                        const initialParams = await this.subject.params();
                        await this.subject
                            .connect(this.admin)
                            .stageParams(params);
                        expect(await this.subject.params()).to.deep.equal(
                            initialParams
                        );
                        return true;
                    }
                );
                pit(
                    `updates by #stageParams + #commitParams`,
                    { numRuns: RUNS.low },
                    paramsArb,
                    async (params: ParamsStruct) => {
                        await this.subject
                            .connect(this.admin)
                            .stageParams(params);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject.connect(this.admin).commitParams();
                        expect(
                            toObject(await this.subject.params())
                        ).to.equivalent(params);
                        return true;
                    }
                );
            });
            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(this.subject.connect(signer).params()).to
                            .not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(this.subject.address).to.not.eql(
                    ethers.constants.AddressZero
                );
            });
        });

        describe("#permissionAddresses", () => {
            describe("properties", () => {
                pit(
                    `updates when committed permission grant for a new address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        const initialPermissionAddresses =
                            await this.subject.permissionAddresses();
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        expect(await this.subject.permissionAddresses()).to.eql(
                            initialPermissionAddresses.concat([target])
                        );
                        await this.subject
                            .connect(this.admin)
                            .revokePermissions(target, [permissionId]);
                        expect(await this.subject.permissionAddresses()).to.eql(
                            initialPermissionAddresses
                        );
                        return true;
                    }
                );
                pit(
                    `doesn't update when committed permission grant for an existing address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x != ethers.constants.AddressZero),
                    uint8.filter((x) => x.lt(100)),
                    uint8.filter((x) => x.gte(100)),
                    async (
                        target: string,
                        permissionId: BigNumber,
                        anotherPermissionId: BigNumber
                    ) => {
                        const initialPermissionAddresses =
                            await this.subject.permissionAddresses();
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        expect(await this.subject.permissionAddresses()).to.eql(
                            initialPermissionAddresses.concat([target])
                        );
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [
                                anotherPermissionId,
                            ]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        expect(await this.subject.permissionAddresses()).to.eql(
                            initialPermissionAddresses.concat([target])
                        );
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).permissionAddresses()
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#stagedPermissionGrantsAddresses", () => {
            describe("properties", () => {
                pit(
                    `updates when staged permission grant for a new address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        expect(
                            await this.subject.stagedPermissionGrantsAddresses()
                        ).to.contain(target);
                        return true;
                    }
                );
                pit(
                    `doesn't update when staged permission grant for an existing address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8.filter((x) => x.lt(100)),
                    uint8.filter((x) => x.gte(100)),
                    async (
                        target: string,
                        permissionId: BigNumber,
                        anotherPermissionId: BigNumber
                    ) => {
                        const initialPermissionAddresses =
                            await this.subject.stagedPermissionGrantsAddresses();
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        expect(
                            await this.subject.stagedPermissionGrantsAddresses()
                        ).to.contain(target);
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [
                                anotherPermissionId,
                            ]);
                        const permissionAddresses =
                            await this.subject.permissionAddresses();
                        expect(permissionAddresses.length).to.eql(
                            permissionAddresses.length
                        );
                        return true;
                    }
                );
                pit(
                    `clears by #commitPermissionGrants`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        expect(
                            await this.subject.stagedPermissionGrantsAddresses()
                        ).to.eql([]);
                        return true;
                    }
                );
                pit(
                    `clears by #rollbackAllPermissionGrants`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await this.subject
                            .connect(this.admin)
                            .rollbackAllPermissionGrants();
                        expect(
                            await this.subject.stagedPermissionGrantsAddresses()
                        ).to.eql([]);
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stagedPermissionGrantsAddresses()
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#addressesByPermission", () => {
            xit("returns addresses that has the given raw permission set to true", async () => {});

            describe("properties", () => {
                pit(
                    `updates by #stagePermissionGrants + #commitPermissionGrants or #revokePermissions`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        expect(
                            await this.subject.addressesByPermission(
                                permissionId
                            )
                        ).to.contain(target);
                        await this.subject
                            .connect(this.admin)
                            .revokePermissions(target, [permissionId]);
                        expect(
                            await this.subject.addressesByPermission(
                                permissionId
                            )
                        ).to.not.contain(target);
                        return true;
                    }
                );
                pit(
                    `is not affected by forceAllowMask`,
                    { numRuns: RUNS.verylow },
                    paramsArb,
                    uint8.filter((x) => x.gt(100)),
                    async (params: ParamsStruct, permissionId: BigNumber) => {
                        params.forceAllowMask = maskByPermissionIds([
                            permissionId,
                        ]);
                        await this.subject
                            .connect(this.admin)
                            .stageParams(params);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject.connect(this.admin).commitParams();
                        // assume that PG already has some addresses listed since deployment
                        expect(
                            await this.subject.addressesByPermission(
                                permissionId
                            )
                        ).to.be.empty;
                        return true;
                    }
                );
                pit(
                    `returns empty array on unknown permissionId`,
                    { numRuns: RUNS.verylow },
                    uint8.filter((x) => x.gt(100)),
                    async (permissionId: BigNumber) => {
                        expect(
                            await this.subject.addressesByPermission(
                                permissionId
                            )
                        ).to.eql([]);
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .addressesByPermission(
                                    generateSingleParams(uint8)
                                )
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#hasPermission", () => {
            describe("properties", () => {
                pit(
                    `returns false on unknown address for any permissionId`,
                    { numRuns: RUNS.verylow },
                    address,
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        expect(
                            await this.subject.hasPermission(
                                target,
                                permissionId
                            )
                        ).to.eql(false);
                        return true;
                    }
                );
                pit(
                    `returns false on known address for unknown permissionId`,
                    { numRuns: RUNS.verylow },
                    address,
                    uint8.filter((x) => x.lte(100)),
                    uint8.filter((x) => x.gt(100)),
                    async (
                        target: string,
                        permissionId: BigNumber,
                        anotherPermissionId: BigNumber
                    ) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        expect(
                            await this.subject.hasPermission(
                                target,
                                anotherPermissionId
                            )
                        ).to.eql(false);
                        return true;
                    }
                );
                pit(
                    `isn't affected by staged permission grants`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8.filter((x) => x.gt(100)),
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        expect(
                            await this.subject.hasPermission(
                                target,
                                permissionId
                            )
                        ).to.eql(false);
                        return true;
                    }
                );
                pit(
                    `is affected by forceAllowMask`,
                    { numRuns: RUNS.verylow },
                    paramsArb,
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (
                        params: ParamsStruct,
                        target: string,
                        permissionId: BigNumber
                    ) => {
                        params.forceAllowMask = maskByPermissionIds([
                            permissionId,
                        ]);
                        await this.subject
                            .connect(this.admin)
                            .stageParams(params);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject.connect(this.admin).commitParams();
                        await this.subject
                            .connect(this.admin)
                            .revokePermissions(target, [permissionId]);
                        expect(
                            await this.subject.hasPermission(
                                target,
                                permissionId
                            )
                        ).to.eql(true);
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .hasPermission(
                                    randomAddress(),
                                    generateSingleParams(uint8)
                                )
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#hasAllPermissions", () => {
            pit(
                `checks if an address has all permissions set to true`,
                { numRuns: RUNS.verylow },
                address.filter((x) => x !== ethers.constants.AddressZero),
                uint8,
                async (target: string, permissionId: BigNumber) => {
                    expect(
                        await this.subject.hasAllPermissions(target, [
                            permissionId,
                        ])
                    ).to.be.false;
                    await this.subject
                        .connect(this.admin)
                        .stagePermissionGrants(target, [permissionId]);
                    await sleep(await this.subject.governanceDelay());
                    await this.subject
                        .connect(this.admin)
                        .commitPermissionGrants(target);
                    expect(
                        await this.subject.hasAllPermissions(target, [
                            permissionId,
                        ])
                    ).to.be.true;
                    return true;
                }
            );

            describe.only("properties", () => {
                pit(
                    `returns false on random address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        expect(
                            await this.subject.hasAllPermissions(target, [
                                permissionId,
                            ])
                        ).to.be.false;
                        return true;
                    }
                );
                pit(
                    `is not affected by staged permissions`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    tuple(uint8, uint8).filter(([x, y]) => !x.eq(y)),
                    async (
                        target: string,
                        [grantedPermissionId, stagedPermissionId]: [
                            BigNumber,
                            BigNumber
                        ]
                    ) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [
                                grantedPermissionId,
                            ]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);

                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [
                                stagedPermissionId,
                            ]);

                        expect(
                            await this.subject.hasAllPermissions(target, [
                                grantedPermissionId,
                            ])
                        ).to.be.true;
                        expect(
                            await this.subject.hasAllPermissions(target, [
                                grantedPermissionId,
                                stagedPermissionId,
                            ])
                        ).to.be.false;
                        return true;
                    }
                );
                pit(
                    `is affected by committed permissions`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, grantedPermissionId: BigNumber) => {
                        assert(
                            !(await this.subject.hasAllPermissions(target, [
                                grantedPermissionId,
                            ])),
                            "Target address mustn't have permission with index grantedPermissionId"
                        );

                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [
                                grantedPermissionId,
                            ]);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);

                        expect(
                            await this.subject.hasAllPermissions(target, [
                                grantedPermissionId,
                            ])
                        ).to.be.true;
                        return true;
                    }
                );
                pit(
                    `returns true for any address when forceAllowMask is set to true`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    tuple(uint8, uint8).filter(([x, y]) => x.gt(y)),
                    paramsArb,
                    async (
                        target: string,
                        [permissionsCount, grantedPermissionId]: [
                            BigNumber,
                            BigNumber
                        ],
                        params: ParamsStruct
                    ) => {
                        params.forceAllowMask = BigNumber.from(2)
                            .pow(permissionsCount)
                            .sub(1);
                        await this.subject
                            .connect(this.admin)
                            .stageParams(params);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject.connect(this.admin).commitParams();
                        let permissionIdList = [];
                        for (let i = 0; permissionsCount.gt(i); ++i) {
                            permissionIdList.push(i);
                        }
                        expect(
                            await this.subject.hasAllPermissions(target, [
                                grantedPermissionId,
                            ])
                        ).to.be.true;
                        expect(
                            await this.subject.hasAllPermissions(
                                target,
                                permissionIdList
                            )
                        ).to.be.true;
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    let signerAddress = randomAddress();
                    await withSigner(signerAddress, async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .hasAllPermissions(signerAddress, [])
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });

            describe("edge cases", () => {
                describe("on unknown permission id", () => {
                    xit("returns false", async () => {});
                });
            });
        });

        xdescribe("#maxTokensPerVault", () => {});

        xdescribe("#governanceDelay", () => {});

        xdescribe("#protocolTreasury", () => {});

        xdescribe("#forceAllowMask", () => {});

        describe("#supportsInterface", () => {
            it(`returns true for IProtocolGovernance interface (${PROTOCOL_GOVERNANCE_INTERFACE_ID})`, async () => {
                expect(
                    await this.subject.supportsInterface(
                        PROTOCOL_GOVERNANCE_INTERFACE_ID
                    )
                ).to.be.true;
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .supportsInterface(
                                    PROTOCOL_GOVERNANCE_INTERFACE_ID
                                )
                        ).to.not.be.reverted;
                    });
                });
            });

            describe("edge cases:", () => {
                describe("when contract does not support the given interface", () => {
                    it("returns false", async () => {
                        expect(
                            await this.subject.supportsInterface(
                                VAULT_INTERFACE_ID
                            )
                        ).to.be.false;
                    });
                });
            });
        });

        describe("#rollbackAllPermissionGrants", () => {
            pit(
                "rolls back all staged permission grants",
                { numRuns: RUNS.verylow },
                address.filter((x) => x !== ethers.constants.AddressZero),
                uint8,
                async (target: string, permissionId: BigNumber) => {
                    await this.subject
                        .connect(this.admin)
                        .stagePermissionGrants(target, [permissionId]);
                    await this.subject
                        .connect(this.admin)
                        .rollbackAllPermissionGrants();
                    expect(await this.subject.stagedPermissionGrantsAddresses())
                        .to.be.empty;
                    expect(
                        await this.subject.stagedPermissionGrantsMasks(target)
                    ).to.deep.equal(BigNumber.from(0));
                    return true;
                }
            );
            it("emits AllPermissionGrantsRolledBack event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .rollbackAllPermissionGrants()
                ).to.emit(this.subject, "AllPermissionGrantsRolledBack");
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rollbackAllPermissionGrants()
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .rollbackAllPermissionGrants()
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .rollbackAllPermissionGrants()
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });

        describe("#commitPermissionGrants", () => {
            pit(
                `commits staged permission grants`,
                { numRuns: RUNS.verylow },
                address.filter((x) => x !== ethers.constants.AddressZero),
                uint8.filter((x) => x.gt(100)),
                async (target: string, permissionId: BigNumber) => {
                    await this.subject
                        .connect(this.admin)
                        .stagePermissionGrants(target, [permissionId]);
                    await sleep(await this.subject.governanceDelay());
                    await this.subject
                        .connect(this.admin)
                        .commitPermissionGrants(target);
                    expect(
                        await this.subject.hasPermission(target, permissionId)
                    ).to.be.true;
                    expect(
                        await this.subject.permissionMasks(target)
                    ).to.deep.equal(maskByPermissionIds([permissionId]));
                    return true;
                }
            );
            pit(
                `emits PermissionGrantsCommitted event`,
                { numRuns: RUNS.verylow },
                address.filter((x) => x !== ethers.constants.AddressZero),
                uint8.filter((x) => x.gt(100)),
                async (target: string, permissionId: BigNumber) => {
                    await this.subject
                        .connect(this.admin)
                        .stagePermissionGrants(target, [permissionId]);
                    await sleep(await this.subject.governanceDelay());
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target)
                    ).to.emit(this.subject, "PermissionGrantsCommitted");
                    return true;
                }
            );

            describe("edge cases", () => {
                describe("when attempting to commit permissions for zero address", () => {
                    it(`reverts with ${Exceptions.NULL}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitPermissionGrants(
                                    ethers.constants.AddressZero
                                )
                        ).to.be.revertedWith(Exceptions.NULL);
                    });
                });

                describe("when nothigh is staged for the given address", () => {
                    it(`reverts with ${Exceptions.NULL}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitPermissionGrants(this.subject.address)
                        ).to.be.revertedWith(Exceptions.NULL);
                    });
                });

                describe("when attempting to commit permissions too early", () => {
                    pit(
                        `reverts with ${Exceptions.TIMESTAMP}`,
                        { numRuns: 1 },
                        address.filter(
                            (x) => x !== ethers.constants.AddressZero
                        ),
                        uint8,
                        async (target: string, permissionId: BigNumber) => {
                            await this.subject
                                .connect(this.admin)
                                .stagePermissionGrants(target, [permissionId]);
                            await sleep(1);
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .commitPermissionGrants(target)
                            ).to.be.revertedWith(Exceptions.TIMESTAMP);
                            return true;
                        }
                    );
                });
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(this.deployer.address, [0])
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .stagePermissionGrants(this.deployer.address, [0])
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stagePermissionGrants(this.deployer.address, [
                                    0,
                                ])
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });

        xdescribe("#commitAllPermissionGrantsSurpassedDelay", () => {});

        describe("#revokePermissions", () => {
            pit(
                `emits PermissionRevoked event`,
                { numRuns: RUNS.verylow },
                address.filter((x) => x !== ethers.constants.AddressZero),
                uint8.filter((x) => x.gt(100)),
                async (target: string, permissionId: BigNumber) => {
                    await this.subject
                        .connect(this.admin)
                        .stagePermissionGrants(target, [permissionId]);
                    await sleep(await this.subject.governanceDelay());
                    await this.subject
                        .connect(this.admin)
                        .commitPermissionGrants(target);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .revokePermissions(target, [permissionId])
                    ).to.emit(this.subject, "PermissionsRevoked");
                    return true;
                }
            );
            describe("edge cases", () => {
                describe("when attempting to revoke from zero address", () => {
                    pit(
                        `reverts with ${Exceptions.NULL}`,
                        { numRuns: RUNS.verylow },
                        uint8,
                        async (permissionId: BigNumber) => {
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .revokePermissions(
                                        ethers.constants.AddressZero,
                                        [permissionId]
                                    )
                            ).to.be.revertedWith(Exceptions.NULL);
                            return true;
                        }
                    );
                });
            });
        });

        describe("#commitParams", () => {
            pit(
                `emits ParamsCommitted event`,
                { numRuns: RUNS.verylow },
                paramsArb,
                async (params: ParamsStruct) => {
                    await this.subject.connect(this.admin).stageParams(params);
                    await sleep(await this.subject.governanceDelay());
                    await expect(
                        this.subject.connect(this.admin).commitParams()
                    ).to.emit(this.subject, "ParamsCommitted");
                    return true;
                }
            );

            describe("edge cases", () => {
                describe("when attempting to commit params too early", () => {
                    pit(
                        `reverts with ${Exceptions.TIMESTAMP}`,
                        { numRuns: 1 },
                        paramsArb,
                        async (params: ParamsStruct) => {
                            await this.subject
                                .connect(this.admin)
                                .stageParams(params);
                            await sleep(1);
                            await expect(
                                this.subject.connect(this.admin).commitParams()
                            ).to.be.revertedWith(Exceptions.TIMESTAMP);
                            return true;
                        }
                    );
                });

                describe("when attempting to commit params without setting pending params", () => {
                    it(`reverts with ${Exceptions.NULL}`, async () => {
                        await expect(
                            this.subject.connect(this.admin).commitParams()
                        ).to.be.revertedWith(Exceptions.NULL);
                        return true;
                    });
                });
            });

            describe("access control", () => {
                it("allowed: protocol admin", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageParams(generateSingleParams(paramsArb));
                    await sleep(await this.subject.governanceDelay());
                    await expect(
                        this.subject.connect(this.admin).commitParams()
                    ).to.not.be.reverted;
                    return true;
                });
                it("denied: deployer", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageParams(generateSingleParams(paramsArb));
                    await sleep(await this.subject.governanceDelay());
                    await expect(
                        this.subject.connect(this.deployer).commitParams()
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    return true;
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .stageParams(generateSingleParams(paramsArb));
                        await sleep(await this.subject.governanceDelay());
                        await expect(
                            this.subject.connect(signer).commitParams()
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });

        describe("#stagePermissionGrants", () => {
            pit(
                `emits PermissionGrantsStaged event`,
                { numRuns: RUNS.verylow },
                address.filter((x) => x !== ethers.constants.AddressZero),
                uint8,
                async (target: string, permissionId: BigNumber) => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId])
                    ).to.emit(this.subject, "PermissionGrantsStaged");
                    return true;
                }
            );

            describe("edge cases", () => {
                describe("when attempting to stage grant to zero address", () => {
                    it("reverts with NULL", async () => {});
                    pit(
                        `reverts with ${Exceptions.NULL}`,
                        { numRuns: RUNS.verylow },
                        uint8,
                        async (permissionId: BigNumber) => {
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .stagePermissionGrants(
                                        ethers.constants.AddressZero,
                                        [permissionId]
                                    )
                            ).to.be.revertedWith(Exceptions.NULL);
                            return true;
                        }
                    );
                });
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(this.deployer.address, [])
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .stagePermissionGrants(this.deployer.address, [])
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stagePermissionGrants(
                                    this.deployer.address,
                                    []
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#stageParams", () => {
            pit(
                `emits ParamsStaged event`,
                { numRuns: RUNS.verylow },
                paramsArb,
                async (params: ParamsStruct) => {
                    await expect(
                        this.subject.connect(this.admin).stageParams(params)
                    ).to.emit(this.subject, "ParamsStaged");
                    return true;
                }
            );

            describe("edge cases", () => {
                describe("when given invalid params", () => {
                    describe("when maxTokensPerVault is zero", () => {
                        pit(
                            `reverts with ${Exceptions.NULL}`,
                            { numRuns: RUNS.verylow },
                            paramsArb,
                            async (params: ParamsStruct) => {
                                params.maxTokensPerVault = BigNumber.from(0);
                                await expect(
                                    this.subject
                                        .connect(this.admin)
                                        .stageParams(params)
                                ).to.be.revertedWith(Exceptions.NULL);
                                return true;
                            }
                        );
                    });

                    describe("when governanceDelay is zero", () => {
                        pit(
                            `reverts with ${Exceptions.NULL}`,
                            { numRuns: RUNS.verylow },
                            paramsArb,
                            async (params: ParamsStruct) => {
                                params.governanceDelay = BigNumber.from(0);
                                await expect(
                                    this.subject
                                        .connect(this.admin)
                                        .stageParams(params)
                                ).to.be.revertedWith(Exceptions.NULL);
                                return true;
                            }
                        );
                    });

                    describe("when governanceDelay exceeds MAX_GOVERNANCE_DELAY", () => {
                        pit(
                            `reverts with ${Exceptions.LIMIT_OVERFLOW}`,
                            { numRuns: RUNS.verylow },
                            paramsArb,
                            async (params: ParamsStruct) => {
                                params.governanceDelay = BigNumber.from(
                                    MAX_GOVERNANCE_DELAY.add(1)
                                );
                                await expect(
                                    this.subject
                                        .connect(this.admin)
                                        .stageParams(params)
                                ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                                return true;
                            }
                        );
                    });
                });
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageParams(generateSingleParams(paramsArb))
                    ).to.not.be.reverted;
                    return true;
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stageParams(generateSingleParams(paramsArb))
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });
    }
);
