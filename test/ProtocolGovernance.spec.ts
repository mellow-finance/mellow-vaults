import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { now, sleep, sleepTo, withSigner } from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import { contract } from "./library/setup";
import { ParamsStruct, IProtocolGovernance } from "./types/IProtocolGovernance";
import { address, uint8, uint256, pit, RUNS } from "./library/property";
import { Arbitrary, tuple, integer } from "fast-check";
import { BigNumber } from "ethers";
import { Contract } from "@ethersproject/contracts";

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
    uint256
).map(
    ([
        maxTokensPerVault,
        governanceDelay,
        protocolTreasury,
        forceAllowMask,
    ]) => ({
        maxTokensPerVault: BigNumber.from(maxTokensPerVault),
        governanceDelay: BigNumber.from(governanceDelay),
        protocolTreasury: protocolTreasury,
        forceAllowMask: BigNumber.from(forceAllowMask),
    })
);

contract<IProtocolGovernance, CustomContext, DeployOptions>(
    "ProtocolGovernance",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
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
                    uint8,
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
                    `returns zero on a random address`,
                    { numRuns: RUNS.verylow },
                    address,
                    async (target: string) => {
                        expect(
                            await this.subject.stagedPermissionGrantsTimestamps(
                                target
                            )
                        ).to.eql(BigNumber.from(0));
                        return true;
                    }
                );
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: 1 },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (target: string, signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .stagedPermissionGrantsTimestamps(target)
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
            });
        });

        describe("#stagedPermissionGrantsMasks", () => {
            describe("properties", () => {
                pit(
                    `updates when #stagePermissionGrants is called`,
                    { numRuns: 1 },
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
                        ).to.eql(maskByPermissionIds([permissionId]));
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
                        ).to.eql(maskByPermissionIds([permissionId]));
                        return true;
                    }
                );
                pit(
                    `clears when #rollbackAllPermissionGrants is called`,
                    { numRuns: 1 },
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
                        ).to.eql(BigNumber.from(0));
                        return true;
                    }
                );
                pit(
                    `returns zero on a random address`,
                    { numRuns: RUNS.verylow },
                    address,
                    async (target: string) => {
                        expect(
                            await this.subject.stagedPermissionGrantsTimestamps(
                                target
                            )
                        ).to.eql(BigNumber.from(0));
                        return true;
                    }
                );
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: 1 },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (target: string, signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .stagedPermissionGrantsMasks(target)
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
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
                        ).to.eql(BigNumber.from(0));
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
                        ).to.eql(maskByPermissionIds([permissionId]));
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
                        ).to.eql(maskByPermissionIds([permissionId]));
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
                        ).to.eql(BigNumber.from(0));
                        return true;
                    }
                );
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: 1 },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (target: string, signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .permissionMasks(target)
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
            });
        });

        describe("#pendingParamsTimestamp", () => {
            pit(
                `when #stagePermissionGrants is called sets timestamp to block.timestamp + governanceDelay`,
                { numRuns: 1 },
                paramsArb,
                async (params: ParamsStruct) => {
                    const governanceDelay: BigNumber =
                        await this.subject.governanceDelay();
                    await this.subject
                        .connect(this.admin)
                        .setPendingParams(params);
                    expect(await this.subject.pendingParamsTimestamp()).to.eql(
                        governanceDelay.add(this.startTimestamp).add(1)
                    );
                    return true;
                }
            );
            pit(
                `clears when #commitParams is called`,
                { numRuns: RUNS.verylow },
                paramsArb,
                async (params: ParamsStruct) => {
                    await this.subject
                        .connect(this.admin)
                        .setPendingParams(params);
                    await sleep(await this.subject.governanceDelay());
                    await this.subject.connect(this.admin).commitParams();
                    expect(await this.subject.pendingParamsTimestamp()).to.eql(
                        BigNumber.from(0)
                    );
                    return true;
                }
            );

            describe("edge cases", () => {
                describe("when nothing is set", () => {
                    it("returns zero", async () => {
                        expect(
                            await this.subject.pendingParamsTimestamp()
                        ).to.eql(BigNumber.from(0));
                    });
                });
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: 1 },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .pendingParamsTimestamp()
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
            });
        });

        describe("#pendingParams", () => {
            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                (this.subject as Contract)
                                    .connect(signer)
                                    .pendingParams()
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
            });
        });

        describe("#params", () => {
            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                (this.subject as Contract)
                                    .connect(signer)
                                    .params()
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
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
                it("@property: address is returned <=> permission mask is not 0", async () => {});
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .permissionAddresses()
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
            });
        });

        describe("#stagedPermissionGrantsAddresses", () => {
            it("returns addresses that has any permission staged to be granted", async () => {});

            describe("properties", () => {
                it("@property: address is returned <=> address had been granted smth", async () => {});
                it("@property: updates when granted permission for a new address", async () => {});
                it("@property: clears when staged permissions committed", async () => {});
                it("@property: unaffected when permissions revoked instantly", async () => {});
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .stagedPermissionGrantsAddresses()
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
            });
        });

        describe("#addressesByPermission", () => {
            it("returns addresses that has the given raw permission set to true", async () => {});

            describe("properties", () => {
                it("@property: updates when the given permission is revoked", async () => {});
                it("@property: unaffected by forceAllowMask", async () => {});
            });

            describe("edge cases", () => {
                describe("on unknown permission id", () => {
                    it("returns empty array", async () => {});
                });
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (signerAddress: string, permissionId: BigNumber) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .addressesByPermission(permissionId)
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
            });
        });

        describe("#hasPermission", () => {
            it("checks if an address has permission", async () => {});

            describe("properties", () => {
                it("@property: returns false on random address", async () => {});
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
                    uint8.filter((x) => x.lte(10)),
                    uint8.filter((x) => x.gt(10)),
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
                    uint8.filter((x) => x.gt(10)),
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
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        // TODO: implement
                        return true;
                    }
                );
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: 1 },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (
                        target: string,
                        signerAddress: string,
                        permissionId: BigNumber
                    ) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .hasPermission(target, permissionId)
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
            });
        });

        describe("#hasAllPermissions", () => {
            it("checks if an address has all permissions set to true", async () => {});

            describe("properties", () => {
                it("@property: returns false on random address", async () => {});
                it("@property: is not affected by staged permissions", async () => {});
                it("@property: is affected by committed permissions", async () => {});
                it("@property: returns true for any address when forceAllowMask is set to true", async () => {});
            });

            describe("access control", () => {
                it("allowed: any address", async () => {});
            });

            describe("edge cases", () => {
                describe("on unknown permission id", () => {
                    it("returns false", async () => {});
                });
            });
        });
    }
);
