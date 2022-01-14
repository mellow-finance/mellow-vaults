import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { now, sleep, sleepTo, toObject, withSigner } from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import { contract } from "./library/setup";
import { ParamsStruct, IProtocolGovernance } from "./types/IProtocolGovernance";
import { address, uint8, uint256, pit, RUNS } from "./library/property";
import { Arbitrary, tuple, integer } from "fast-check";
import { BigNumber } from "ethers";

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

const emptyParams: ParamsStruct = {
    maxTokensPerVault: BigNumber.from(0),
    governanceDelay: BigNumber.from(0),
    protocolTreasury: ethers.constants.AddressZero,
    forceAllowMask: BigNumber.from(0),
};

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
                    `returns zero on unknown address`,
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
                    `returns zero on unknown address`,
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
                `timestamp equals #setPendingParams's block.timestamp + governanceDelay`,
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
                `clears by #commitParams`,
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
            describe("properties", () => {
                pit(
                    `updates by #setPendingParams`,
                    { numRuns: RUNS.verylow },
                    paramsArb,
                    async (params: ParamsStruct) => {
                        await this.subject
                            .connect(this.admin)
                            .setPendingParams(params);
                        expect(
                            toObject(await this.subject.pendingParams())
                        ).to.eql(params);
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
                            .setPendingParams(params);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject.connect(this.admin).commitParams();
                        expect(
                            toObject(await this.subject.pendingParams())
                        ).to.eql(emptyParams);
                        return true;
                    }
                );
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(
                                this.subject.connect(signer).pendingParams()
                            ).to.not.be.reverted;
                        });
                        return true;
                    }
                );
            });
        });

        describe("#params", () => {
            describe("properties", () => {
                pit(
                    `is not affected by #setPendingParams`,
                    { numRuns: RUNS.verylow },
                    paramsArb,
                    async (params: ParamsStruct) => {
                        const initialParams = await this.subject.params();
                        await this.subject
                            .connect(this.admin)
                            .setPendingParams(params);
                        expect(await this.subject.params()).to.eql(
                            initialParams
                        );
                        return true;
                    }
                );
                pit(
                    `updates by #setPendingParams + #commitParams`,
                    { numRuns: RUNS.verylow },
                    paramsArb,
                    async (params: ParamsStruct) => {
                        await this.subject
                            .connect(this.admin)
                            .setPendingParams(params);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject.connect(this.admin).commitParams();
                        expect(toObject(await this.subject.params())).to.eql(
                            params
                        );
                        return true;
                    }
                );
            });
            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await expect(this.subject.connect(signer).params())
                                .to.not.be.reverted;
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
                // pit(
                //     `doesn't update when committed permission grant for an existing address`,
                //     { numRuns: RUNS.verylow },
                //     address.filter((x) => x != ethers.constants.AddressZero),
                //     uint8.filter((x) => x.lt(100)),
                //     uint8.filter((x) => x.gte(100)),
                //     async (
                //         target: string,
                //         permissionId: BigNumber,
                //         anotherPermissionId: BigNumber
                //     ) => {
                //         const initialPermissionAddresses =
                //             await this.subject.permissionAddresses();
                //         await this.subject
                //             .connect(this.admin)
                //             .stagePermissionGrants(target, [permissionId]);
                //         await sleep(await this.subject.governanceDelay());
                //         await this.subject
                //             .connect(this.admin)
                //             .commitPermissionGrants(target);
                //         expect(await this.subject.permissionAddresses()).to.eql(
                //             initialPermissionAddresses.concat([target])
                //         );
                //         await this.subject
                //             .connect(this.admin)
                //             .stagePermissionGrants(target, [
                //                 anotherPermissionId,
                //             ]);
                //         await sleep(await this.subject.governanceDelay());
                //         await this.subject
                //             .connect(this.admin)
                //             .commitPermissionGrants(target);
                //         expect(await this.subject.permissionAddresses()).to.eql(
                //             initialPermissionAddresses.concat([target])
                //         );
                //         return true;
                //     }
                // );
            });

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x != ethers.constants.AddressZero),
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
            describe("properties", () => {
                pit(
                    `updates when staged permission grant for a new address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        const initialPermissionAddresses =
                            await this.subject.stagedPermissionGrantsAddresses();
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        expect(
                            await this.subject.stagedPermissionGrantsAddresses()
                        ).to.eql(initialPermissionAddresses.concat([target]));
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
                        ).to.eql(initialPermissionAddresses.concat([target]));
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [
                                anotherPermissionId,
                            ]);
                        expect(await this.subject.permissionAddresses()).to.eql(
                            initialPermissionAddresses.concat([target])
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
                        ).to.eql([target]);
                        await this.subject
                            .connect(this.admin)
                            .revokePermissions(target, [permissionId]);
                        expect(
                            await this.subject.addressesByPermission(
                                permissionId
                            )
                        ).to.eql([]);
                        return true;
                    }
                );
                pit(
                    `is not affected by forceAllowMask`,
                    { numRuns: RUNS.verylow },
                    paramsArb,
                    uint8,
                    async (params: ParamsStruct, permissionId: BigNumber) => {
                        params.forceAllowMask = maskByPermissionIds([
                            permissionId,
                        ]);
                        await this.subject
                            .connect(this.admin)
                            .setPendingParams(params);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject.connect(this.admin).commitParams();
                        // assume that PG already has some addresses listed since deployment
                        expect(
                            await this.subject.addressesByPermission(
                                permissionId
                            )
                        ).to.eql([]);
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
                            .setPendingParams(params);
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

        describe("#maxTokensPerVault", () => {
            // TODO: implement
        });

        describe("#governanceDelay", () => {
            // TODO: implement
        });

        describe("#protocolTreasury", () => {
            // TODO: implement
        });

        describe("#forceAllowMask", () => {
            // TODO: implement
        });

        describe("#supportsInterface", () => {
            // TODO: implement
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
                    expect(
                        await this.subject.stagedPermissionGrantsAddresses()
                    ).to.eql([]);
                    expect(
                        await this.subject.stagedPermissionGrantsMasks(target)
                    ).to.eql(BigNumber.from(0));
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
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
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
                    ).to.eql(true);
                    expect(await this.subject.permissionMasks(target)).to.eql(
                        maskByPermissionIds([permissionId])
                    );
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
            });

            describe("access control", () => {
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });

        describe("#commitAllPermissionGrantsSurpassedDelay", () => {
            // TODO: implement
        });

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
                        { numRuns: 1 },
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
                `emits PendingParamsCommitted event`,
                { numRuns: 1 },
                paramsArb,
                async (params: ParamsStruct) => {
                    await this.subject.connect(this.admin).setPendingParams(params);
                    await sleep(await this.subject.governanceDelay());
                    await expect(
                        this.subject.connect(this.admin).commitParams()
                    ).to.emit(this.subject, "PendingParamsCommitted");
                    return true;
                }
            );

            describe("access control", () => {
                it("allowed: protocol admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });

        describe("#stagePermissionGrants", () => {
            pit(
                `emits PermissionGrantsStaged event`,
                { numRuns: 1 },
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
                        { numRuns: 1 },
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
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });

        describe("#setPendingParams", () => {
            pit(
                `emits ParamsCommitted event`,
                { numRuns: RUNS.verylow },
                paramsArb,
                async (params: ParamsStruct) => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .setPendingParams(params)
                    ).to.emit(this.subject, "ParamsCommitted");
                    return true;
                }
            );

            describe("edge cases", () => {
                describe("when given invalid params", () => {
                    describe("when maxTokensPerVault is zero", () => {
                        pit(
                            `reverts with ${Exceptions.NULL}`,
                            { numRuns: 1 },
                            paramsArb,
                            async (params: ParamsStruct) => {
                                params.maxTokensPerVault = BigNumber.from(0);
                                await expect(
                                    this.subject.connect(this.admin).setPendingParams(params)
                                ).to.be.revertedWith(Exceptions.NULL);
                                return true;
                            }
                        );
                    });

                    describe("when governanceDelay is zero", () => {
                        pit(
                            `reverts with ${Exceptions.NULL}`,
                            { numRuns: 1 },
                            paramsArb,
                            async (params: ParamsStruct) => {
                                params.governanceDelay = BigNumber.from(0);
                                await expect(
                                    this.subject.connect(this.admin).setPendingParams(params)
                                ).to.be.revertedWith(Exceptions.NULL);
                                return true;
                            }
                        );
                    });

                    describe("when governanceDelay exceeds MAX_GOVERNANCE_DELAY", () => {
                        pit(
                            `reverts with ${Exceptions.LIMIT_OVERFLOW}`,
                            { numRuns: 1 },
                            paramsArb,
                            async (params: ParamsStruct) => {
                                params.governanceDelay = BigNumber.from(
                                    MAX_GOVERNANCE_DELAY.add(1)
                                );
                                await expect(
                                    this.subject.connect(this.admin).setPendingParams(params)
                                ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                                return true;
                            }
                        );
                    });
                });
            });

            describe("access control", () => {
                it("allowed: admin", async () => {});
                it("denied: random address", async () => {});
            });
        });
    }
);
