import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { now, sleep, sleepTo, withSigner } from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import { contract } from "./library/setup";
import { ParamsStruct, IProtocolGovernance } from "./types/IProtocolGovernance";
import { address, uint8, uint256, pit, RUNS } from "./library/property";
import { Arbitrary } from "fast-check";
import { tuple, integer } from "fast-check";
import { BigNumber } from "ethers";

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
                            await this.subject
                                .connect(signer)
                                .stagedPermissionGrantsTimestamps(target);
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
                            await this.subject
                                .connect(signer)
                                .stagedPermissionGrantsMasks(target);
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
                            await this.subject
                                .connect(signer)
                                .permissionMasks(target);
                        });
                        return true;
                    }
                );
            });
        });

        describe("#pendingParamsTimestamp", () => {
            pit(
                `timestamp equals #stagePermissionGrants's block.timestamp + governanceDelay`,
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

            describe("access control", () => {
                pit(
                    `allowed: any address`,
                    { numRuns: 1 },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (signerAddress: string) => {
                        await withSigner(signerAddress, async (signer) => {
                            await this.subject
                                .connect(signer)
                                .pendingParamsTimestamp();
                        });
                        return true;
                    }
                );
            });
        });
    }
);
