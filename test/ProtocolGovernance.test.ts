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
import { Arbitrary, tuple, integer, Random, bigUintN } from "fast-check";
import { BigNumber } from "ethers";
import {
    PROTOCOL_GOVERNANCE_INTERFACE_ID,
    VAULT_INTERFACE_ID,
} from "./library/Constants";
import assert from "assert";
import { randomInt } from "crypto";
import { Address } from "hardhat-deploy/types";

const MAX_GOVERNANCE_DELAY = BigNumber.from(60 * 60 * 24 * 7);
const MIN_WITHDRAW_LIMIT = BigNumber.from(200 * 1000);

type CustomContext = {};
type DeployOptions = {};

function maskByPermissionIds(permissionIds: BigNumber[]): BigNumber {
    let mask = BigNumber.from(0);
    for (let i = 0; i < permissionIds.length; i++) {
        mask = mask.or(BigNumber.from(1).shl(Number(permissionIds[i])));
    }
    return mask;
}

function permissionIdsByMask(mask: BigNumber): BigNumber[] {
    let permissionIds = [];
    for (let permissionId = 0; permissionId < 256; ++permissionId) {
        if (mask.shr(permissionId).and(1).eq(1)) {
            permissionIds.push(BigNumber.from(permissionId));
        }
    }
    return permissionIds;
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
                    `clears when #rollbackStagedPermissionGrants is called`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint8,
                    async (target: string, permissionId: BigNumber) => {
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, [permissionId]);
                        await this.subject
                            .connect(this.admin)
                            .rollbackStagedPermissionGrants();
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
                    `is not affected by #rollbackStagedPermissionGrants`,
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
                            .rollbackStagedPermissionGrants();
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
            it("timestamp equals #stageParams's block.timestamp + governanceDelay", async () => {
                const governanceDelay: BigNumber =
                    await this.subject.governanceDelay();
                await this.subject
                    .connect(this.admin)
                    .stageParams(generateSingleParams(paramsArb));
                expect(await this.subject.stagedParamsTimestamp()).to.eql(
                    governanceDelay.add(this.startTimestamp).add(1)
                );
                return true;
            });
            it("clears by #commitParams", async () => {
                await this.subject
                    .connect(this.admin)
                    .stageParams(generateSingleParams(paramsArb));
                await sleep(await this.subject.governanceDelay());
                await this.subject.connect(this.admin).commitParams();
                expect(
                    await this.subject.stagedParamsTimestamp()
                ).to.deep.equal(BigNumber.from(0));
                return true;
            });

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
                    uint256.filter((x) => x.gt(0)),
                    async (target: string, permissionMask: BigNumber) => {
                        const initialPermissionAddresses =
                            await this.subject.permissionAddresses();
                        let permissionIds = permissionIdsByMask(permissionMask);
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, permissionIds);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        expect(await this.subject.permissionAddresses()).to.eql(
                            initialPermissionAddresses.concat([target])
                        );
                        await this.subject
                            .connect(this.admin)
                            .revokePermissions(target, permissionIds);
                        expect(await this.subject.permissionAddresses()).to.eql(
                            initialPermissionAddresses
                        );
                        return true;
                    }
                );
                pit(
                    `doesn't update when committed permission grant for an existing address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    tuple(uint256, uint256).filter(
                        ([x, y]) => !x.or(y).eq(x) && x.gt(0)
                    ),
                    async (
                        target: string,
                        [permissionMask, anotherPermissionMask]: [
                            BigNumber,
                            BigNumber
                        ]
                    ) => {
                        let permissionIds = permissionIdsByMask(permissionMask);
                        let anotherPermissionIds = permissionIdsByMask(
                            anotherPermissionMask
                        );
                        const initialPermissionAddresses =
                            await this.subject.permissionAddresses();
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, permissionIds);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);
                        expect(await this.subject.permissionAddresses()).to.eql(
                            initialPermissionAddresses.concat([target])
                        );
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                target,
                                anotherPermissionIds
                            );
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

        describe("#validatorsAddress", () => {
            it("returns correct value", async () => {
                let targetAddress = randomAddress();
                let validatorAddress = randomAddress();
                let validatorIndex = (await this.subject.validatorsAddresses())
                    .length;
                await this.subject
                    .connect(this.admin)
                    .stageValidator(targetAddress, validatorAddress);
                await sleep(await this.subject.governanceDelay());
                await this.subject
                    .connect(this.admin)
                    .commitValidator(targetAddress);
                expect(
                    await this.subject.validatorsAddress(validatorIndex)
                ).to.deep.equal(targetAddress);
            });
        });

        describe("#validatorsAddresses", () => {
            describe("properties", () => {
                pit(
                    `updates when committed validator grant for a new address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (target: string, validatorAddress: string) => {
                        const initialValidatorsAddresses =
                            await this.subject.validatorsAddresses();
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(target, validatorAddress);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitValidator(target);
                        expect(await this.subject.validatorsAddresses()).to.eql(
                            initialValidatorsAddresses.concat([target])
                        );
                        await this.subject
                            .connect(this.admin)
                            .revokeValidator(target);
                        expect(await this.subject.validatorsAddresses()).to.eql(
                            initialValidatorsAddresses
                        );
                        return true;
                    }
                );
                pit(
                    `doesn't update when committed validator grant for an existing address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (
                        target: string,
                        validatorAddress: string,
                        anotherValidatorAddress: string
                    ) => {
                        const initialValidatorsAddresses =
                            await this.subject.validatorsAddresses();
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(target, validatorAddress);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitValidator(target);
                        expect(await this.subject.validatorsAddresses()).to.eql(
                            initialValidatorsAddresses.concat([target])
                        );
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(target, anotherValidatorAddress);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitValidator(target);
                        expect(await this.subject.validatorsAddresses()).to.eql(
                            initialValidatorsAddresses.concat([target])
                        );
                        return true;
                    }
                );
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).validatorsAddresses()
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
                    uint256.filter((x) => x.gt(0)),
                    async (target: string, permissionMask: BigNumber) => {
                        let permissionIds = permissionIdsByMask(permissionMask);
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, permissionIds);
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
                    tuple(uint256, uint256).filter(
                        ([x, y]) => !x.or(y).eq(x) && x.gt(0)
                    ),
                    async (
                        target: string,
                        [stagedPermissionMask, anotherStagedPermissionMask]: [
                            BigNumber,
                            BigNumber
                        ]
                    ) => {
                        let stagedPermissionIds =
                            permissionIdsByMask(stagedPermissionMask);
                        let anotherStagedPermissionIds = permissionIdsByMask(
                            anotherStagedPermissionMask
                        );
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, stagedPermissionIds);
                        expect(
                            await this.subject.stagedPermissionGrantsAddresses()
                        ).to.contain(target);
                        const currentPermissionAddresses =
                            await this.subject.stagedPermissionGrantsAddresses();
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                target,
                                anotherStagedPermissionIds
                            );
                        expect(
                            (
                                await this.subject.stagedPermissionGrantsAddresses()
                            ).length
                        ).to.eql(currentPermissionAddresses.length);
                        return true;
                    }
                );
                pit(
                    `clears by #commitPermissionGrants`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint256.filter((x) => x.gt(0)),
                    async (target: string, permissionMask: BigNumber) => {
                        let permissionIds = permissionIdsByMask(permissionMask);
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, permissionIds);
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
                    `clears by #rollbackStagedPermissionGrants`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint256.filter((x) => x.gt(0)),
                    async (target: string, permissionMask: BigNumber) => {
                        let permissionIds = permissionIdsByMask(permissionMask);
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, permissionIds);
                        await this.subject
                            .connect(this.admin)
                            .rollbackStagedPermissionGrants();
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

        describe("#stagedValidatorsAddresses", () => {
            describe("properties", () => {
                pit(
                    `updates when validator grant for a new address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (target: string, validatorAddress: string) => {
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(target, validatorAddress);
                        expect(
                            await this.subject.stagedValidatorsAddresses()
                        ).to.contain(target);
                        return true;
                    }
                );
                pit(
                    `doesn't update when staged validator grant for an existing address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (
                        target: string,
                        validatorAddress: string,
                        anotherValidatorAddress: string
                    ) => {
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(target, validatorAddress);
                        expect(
                            await this.subject.stagedValidatorsAddresses()
                        ).to.contain(target);
                        const currentValidatorAddresses =
                            await this.subject.stagedValidatorsAddresses();
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(target, anotherValidatorAddress);
                        expect(
                            (await this.subject.stagedValidatorsAddresses())
                                .length
                        ).to.eql(currentValidatorAddresses.length);
                        return true;
                    }
                );
                pit(
                    `clears by #commitValidator`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (target: string, validatorAddress: string) => {
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(target, validatorAddress);
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitValidator(target);
                        expect(
                            await this.subject.stagedValidatorsAddresses()
                        ).to.eql([]);
                        return true;
                    }
                );
                pit(
                    `clears by #rollbackStagedValidators`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (target: string, validatorAddress: string) => {
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(target, validatorAddress);
                        await this.subject
                            .connect(this.admin)
                            .rollbackStagedValidators();
                        expect(
                            await this.subject.stagedValidatorsAddresses()
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
                                .stagedValidatorsAddresses()
                        ).to.not.be.reverted;
                    });
                    return true;
                });
            });
        });

        describe("#addressesByPermission", () => {
            it("returns addresses that has the given permission set to true", async () => {
                let targetAddress = randomAddress();
                let permissionId = generateSingleParams(uint8);
                await this.subject
                    .connect(this.admin)
                    .stagePermissionGrants(targetAddress, [permissionId]);
                await sleep(await this.subject.governanceDelay());
                await this.subject
                    .connect(this.admin)
                    .commitPermissionGrants(targetAddress);

                expect(
                    await this.subject.addressesByPermission(permissionId)
                ).to.contain(targetAddress);
                return true;
            });

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
                    tuple(uint8, uint8).filter(
                        ([x, y]) => !x.eq(y) && y.gt(100)
                    ),
                    async (
                        target: string,
                        [permissionId, anotherPermissionId]: [
                            BigNumber,
                            BigNumber
                        ]
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
            it(`checks if an address has all permissions set to true`, async () => {
                let targetAddress = randomAddress();
                let permissionIds = permissionIdsByMask(
                    generateSingleParams(uint256.filter((x) => x.gt(0)))
                );
                expect(
                    await this.subject.hasAllPermissions(
                        targetAddress,
                        permissionIds
                    )
                ).to.be.false;
                await this.subject
                    .connect(this.admin)
                    .stagePermissionGrants(targetAddress, permissionIds);
                await sleep(await this.subject.governanceDelay());
                await this.subject
                    .connect(this.admin)
                    .commitPermissionGrants(targetAddress);
                expect(
                    await this.subject.hasAllPermissions(
                        targetAddress,
                        permissionIds
                    )
                ).to.be.true;
                return true;
            });

            describe("properties", () => {
                pit(
                    `returns false on random address`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint256.filter((x) => x.gt(0)),
                    async (target: string, permissionMask: BigNumber) => {
                        let permissionIds = permissionIdsByMask(permissionMask);
                        expect(
                            await this.subject.hasAllPermissions(
                                target,
                                permissionIds
                            )
                        ).to.be.false;
                        return true;
                    }
                );
                pit(
                    `is not affected by staged permissions`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    tuple(uint256, uint256).filter(
                        ([x, y]) => !x.or(y).eq(x) && x.gt(0)
                    ),
                    async (
                        target: string,
                        [grantedPermissionMask, stagedPermissionMask]: [
                            BigNumber,
                            BigNumber
                        ]
                    ) => {
                        let grantedPermissionIds = permissionIdsByMask(
                            grantedPermissionMask
                        );
                        let stagedPermissionIds =
                            permissionIdsByMask(stagedPermissionMask);
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                target,
                                grantedPermissionIds
                            );
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);

                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(target, stagedPermissionIds);

                        expect(
                            await this.subject.hasAllPermissions(
                                target,
                                grantedPermissionIds
                            )
                        ).to.be.true;
                        expect(
                            await this.subject.hasAllPermissions(
                                target,
                                permissionIdsByMask(
                                    grantedPermissionMask.or(
                                        stagedPermissionMask
                                    )
                                )
                            )
                        ).to.be.false;
                        return true;
                    }
                );
                pit(
                    `is affected by committed permissions`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    uint256.filter((x) => x.gt(0)),
                    async (
                        target: string,
                        grantedPermissionMask: BigNumber
                    ) => {
                        let grantedPermissionIds = permissionIdsByMask(
                            grantedPermissionMask
                        );
                        assert(
                            !(await this.subject.hasAllPermissions(
                                target,
                                grantedPermissionIds
                            )),
                            "Target address mustn't have permission with index grantedPermissionId"
                        );

                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                target,
                                grantedPermissionIds
                            );
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(target);

                        expect(
                            await this.subject.hasAllPermissions(
                                target,
                                grantedPermissionIds
                            )
                        ).to.be.true;
                        return true;
                    }
                );
                pit(
                    `returns true for any address when forceAllowMask is set to true`,
                    { numRuns: RUNS.verylow },
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    tuple(uint8, uint256).filter(([x, y]) =>
                        BigNumber.from(1).shl(Number(x)).gt(y)
                    ),
                    paramsArb,
                    async (
                        target: string,
                        [permissionsCount, grantedPermissionMask]: [
                            BigNumber,
                            BigNumber
                        ],
                        params: ParamsStruct
                    ) => {
                        let grantedPermissionIds = permissionIdsByMask(
                            grantedPermissionMask
                        );
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
                            await this.subject.hasAllPermissions(
                                target,
                                grantedPermissionIds
                            )
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
                    it("returns false", async () => {
                        expect(
                            await this.subject.hasAllPermissions(
                                randomAddress(),
                                [
                                    generateSingleParams(
                                        uint8.filter((x) => x.gt(240))
                                    ),
                                ]
                            )
                        ).to.be.false;
                        return true;
                    });
                });
            });
        });

        describe("#maxTokensPerVault", () => {
            it("returns correct value", async () => {
                let params = generateSingleParams(paramsArb);
                await this.subject.connect(this.admin).stageParams(params);
                await sleep(await this.subject.governanceDelay());
                await this.subject.connect(this.admin).commitParams();
                expect(await this.subject.maxTokensPerVault()).to.deep.equal(
                    params.maxTokensPerVault
                );
                return true;
            });
        });

        describe("#governanceDelay", () => {
            it("returns correct value", async () => {
                let params = generateSingleParams(paramsArb);
                await this.subject.connect(this.admin).stageParams(params);
                await sleep(await this.subject.governanceDelay());
                await this.subject.connect(this.admin).commitParams();
                expect(await this.subject.governanceDelay()).to.deep.equal(
                    params.governanceDelay
                );
                return true;
            });
        });

        describe("#protocolTreasury", () => {
            it("returns correct value", async () => {
                let params = generateSingleParams(paramsArb);
                await this.subject.connect(this.admin).stageParams(params);
                await sleep(await this.subject.governanceDelay());
                await this.subject.connect(this.admin).commitParams();
                expect(await this.subject.protocolTreasury()).to.deep.equal(
                    params.protocolTreasury
                );
                return true;
            });
        });

        describe("#forceAllowMask", () => {
            it("returns correct value", async () => {
                let params = generateSingleParams(paramsArb);
                await this.subject.connect(this.admin).stageParams(params);
                await sleep(await this.subject.governanceDelay());
                await this.subject.connect(this.admin).commitParams();
                expect(await this.subject.forceAllowMask()).to.deep.equal(
                    params.forceAllowMask
                );
                return true;
            });
        });

        describe("#withdrawLimit", () => {
            it("returns correct value", async () => {
                let params = generateSingleParams(paramsArb);
                params.withdrawLimit = generateSingleParams(
                    bigUintN(160)
                        .map((x: bigint) => BigNumber.from(x.toString()))
                        .filter((x) => x.gt(200_000))
                );
                await this.subject.connect(this.admin).stageParams(params);
                await sleep(await this.subject.governanceDelay());
                await this.subject.connect(this.admin).commitParams();
                expect(
                    await this.subject.withdrawLimit(this.usdc.address)
                ).to.deep.equal(
                    BigNumber.from(params.withdrawLimit).mul(
                        BigNumber.from(10).pow(6)
                    )
                );
                return true;
            });
        });

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

        describe("#rollbackStagedPermissionGrants", () => {
            it("rolls back all staged permission grants", async () => {
                let targetAddress = randomAddress();
                let permissionIds = permissionIdsByMask(
                    generateSingleParams(uint256.filter((x) => x.gt(0)))
                );
                await this.subject
                    .connect(this.admin)
                    .stagePermissionGrants(targetAddress, permissionIds);
                await this.subject
                    .connect(this.admin)
                    .rollbackStagedPermissionGrants();
                expect(await this.subject.stagedPermissionGrantsAddresses()).to
                    .be.empty;
                expect(
                    await this.subject.stagedPermissionGrantsMasks(
                        targetAddress
                    )
                ).to.deep.equal(BigNumber.from(0));
                return true;
            });

            it("emits AllStagedPermissionGrantsRolledBack event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .rollbackStagedPermissionGrants()
                ).to.emit(this.subject, "AllStagedPermissionGrantsRolledBack");
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rollbackStagedPermissionGrants()
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .rollbackStagedPermissionGrants()
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .rollbackStagedPermissionGrants()
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });

        describe("#rollbackStagedValidators", () => {
            it("rolls back all staged validators", async () => {
                let targetAddress = randomAddress();
                let validatorAddress = randomAddress();
                await this.subject
                    .connect(this.admin)
                    .stageValidator(targetAddress, validatorAddress);
                await this.subject
                    .connect(this.admin)
                    .rollbackStagedValidators();
                expect(await this.subject.stagedValidatorsAddresses()).to.be
                    .empty;
                return true;
            });

            it("emits AllStagedValidatorsRolledBack event", async () => {
                await expect(
                    this.subject.connect(this.admin).rollbackStagedValidators()
                ).to.emit(this.subject, "AllStagedValidatorsRolledBack");
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rollbackStagedValidators()
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .rollbackStagedValidators()
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .rollbackStagedValidators()
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });

        describe("#commitPermissionGrants", () => {
            it("commits staged permission grants", async () => {
                let targetAddress = randomAddress();
                let permissionMask = generateSingleParams(
                    uint256.filter((x) => x.gt(0))
                );
                let permissionIds = permissionIdsByMask(permissionMask);
                await this.subject
                    .connect(this.admin)
                    .stagePermissionGrants(targetAddress, permissionIds);
                await sleep(await this.subject.governanceDelay());
                await this.subject
                    .connect(this.admin)
                    .commitPermissionGrants(targetAddress);
                expect(
                    await this.subject.hasAllPermissions(
                        targetAddress,
                        permissionIds
                    )
                ).to.be.true;
                expect(
                    await this.subject.permissionMasks(targetAddress)
                ).to.deep.equal(permissionMask);
                return true;
            });
            it("emits PermissionGrantsCommitted event", async () => {
                let targetAddress = randomAddress();
                let permissionIds = permissionIdsByMask(
                    generateSingleParams(uint256.filter((x) => x.gt(0)))
                );
                await this.subject
                    .connect(this.admin)
                    .stagePermissionGrants(targetAddress, permissionIds);
                await sleep(await this.subject.governanceDelay());
                await expect(
                    this.subject
                        .connect(this.admin)
                        .commitPermissionGrants(targetAddress)
                ).to.emit(this.subject, "PermissionGrantsCommitted");
                return true;
            });

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

                describe("when nothing is staged for the given address", () => {
                    it(`reverts with ${Exceptions.NULL}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitPermissionGrants(this.subject.address)
                        ).to.be.revertedWith(Exceptions.NULL);
                    });
                });

                describe("when attempting to commit permissions too early", () => {
                    it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                        let targetAddress = randomAddress();
                        let permissionIds = permissionIdsByMask(
                            generateSingleParams(uint256.filter((x) => x.gt(0)))
                        );
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                targetAddress,
                                permissionIds
                            );
                        await sleep(1);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitPermissionGrants(targetAddress)
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                        return true;
                    });
                });
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    let targetAddress = randomAddress();
                    let permissionIds = permissionIdsByMask(
                        generateSingleParams(uint256.filter((x) => x.gt(0)))
                    );
                    await this.subject
                        .connect(this.admin)
                        .stagePermissionGrants(targetAddress, permissionIds);
                    await sleep(await this.subject.governanceDelay());
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitPermissionGrants(targetAddress)
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    let targetAddress = randomAddress();
                    let permissionIds = permissionIdsByMask(
                        generateSingleParams(uint256.filter((x) => x.gt(0)))
                    );
                    await this.subject
                        .connect(this.admin)
                        .stagePermissionGrants(targetAddress, permissionIds);
                    await sleep(await this.subject.governanceDelay());
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .commitPermissionGrants(targetAddress)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    let targetAddress = randomAddress();
                    let permissionIds = permissionIdsByMask(
                        generateSingleParams(uint256.filter((x) => x.gt(0)))
                    );
                    await this.subject
                        .connect(this.admin)
                        .stagePermissionGrants(targetAddress, permissionIds);
                    await sleep(await this.subject.governanceDelay());
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .commitPermissionGrants(targetAddress)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });

        describe("#commitValidator", () => {
            it("commits staged validators", async () => {
                let targetAddress = randomAddress();
                let validatorAddress = randomAddress();
                await this.subject
                    .connect(this.admin)
                    .stageValidator(targetAddress, validatorAddress);
                await sleep(await this.subject.governanceDelay());
                await this.subject
                    .connect(this.admin)
                    .commitValidator(targetAddress);
                expect(await this.subject.validatorsAddresses()).to.contain(
                    targetAddress
                );
                return true;
            });
            it("emits ValidatorCommitted event", async () => {
                let targetAddress = randomAddress();
                let validatorAddress = randomAddress();
                await this.subject
                    .connect(this.admin)
                    .stageValidator(targetAddress, validatorAddress);
                await sleep(await this.subject.governanceDelay());
                await expect(
                    this.subject
                        .connect(this.admin)
                        .commitValidator(targetAddress)
                ).to.emit(this.subject, "ValidatorCommitted");
                return true;
            });

            describe("edge cases", () => {
                describe("when attempting to commit validator for zero address", () => {
                    it(`reverts with ${Exceptions.NULL}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitValidator(ethers.constants.AddressZero)
                        ).to.be.revertedWith(Exceptions.NULL);
                    });
                });

                describe("when nothing is staged for the given address", () => {
                    it(`reverts with ${Exceptions.NULL}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitValidator(this.subject.address)
                        ).to.be.revertedWith(Exceptions.NULL);
                    });
                });

                describe("when attempting to commit validator too early", () => {
                    it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                        let targetAddress = randomAddress();
                        let validatorAddress = randomAddress();
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(targetAddress, validatorAddress);
                        await sleep(1);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitValidator(targetAddress)
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                        return true;
                    });
                });
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    let targetAddress = randomAddress();
                    let validatorAddress = randomAddress();
                    await this.subject
                        .connect(this.admin)
                        .stageValidator(targetAddress, validatorAddress);
                    await sleep(await this.subject.governanceDelay());
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitValidator(targetAddress)
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    let targetAddress = randomAddress();
                    let validatorAddress = randomAddress();
                    await this.subject
                        .connect(this.admin)
                        .stageValidator(targetAddress, validatorAddress);
                    await sleep(await this.subject.governanceDelay());
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .commitValidator(targetAddress)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    let targetAddress = randomAddress();
                    let validatorAddress = randomAddress();
                    await this.subject
                        .connect(this.admin)
                        .stageValidator(targetAddress, validatorAddress);
                    await sleep(await this.subject.governanceDelay());
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .commitValidator(targetAddress)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });

        describe("#commitAllPermissionGrantsSurpassedDelay", () => {
            it("emits PermissionGrantsCommitted event", async () => {
                let targetAddress = randomAddress();
                let permissionIds = permissionIdsByMask(
                    generateSingleParams(uint256.filter((x) => x.gt(0)))
                );
                await this.subject
                    .connect(this.admin)
                    .stagePermissionGrants(targetAddress, permissionIds);
                await sleep(await this.subject.governanceDelay());
                await expect(
                    this.subject
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay()
                ).to.emit(this.subject, "PermissionGrantsCommitted");
                return true;
            });

            describe("properties", () => {
                pit(
                    `commits all staged permission grants`,
                    { numRuns: RUNS.verylow },
                    tuple(address, address).filter(
                        ([x, y]) =>
                            x !== y &&
                            x !== ethers.constants.AddressZero &&
                            y !== ethers.constants.AddressZero
                    ),
                    uint256.filter((x) => x.gt(0)),
                    uint256.filter((x) => x.gt(0)),
                    async (
                        [targetAddress, anotherTargetAddress]: [string, string],
                        permissionMask: BigNumber,
                        anotherPermissionMask: BigNumber
                    ) => {
                        let permissionIds = permissionIdsByMask(permissionMask);
                        let anotherPermissionIds = permissionIdsByMask(
                            anotherPermissionMask
                        );
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                targetAddress,
                                permissionIds
                            );
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                anotherTargetAddress,
                                anotherPermissionIds
                            );
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitAllPermissionGrantsSurpassedDelay();
                        expect(
                            await this.subject.hasAllPermissions(
                                targetAddress,
                                permissionIds
                            )
                        ).to.be.true;
                        expect(
                            await this.subject.hasAllPermissions(
                                anotherTargetAddress,
                                anotherPermissionIds
                            )
                        ).to.be.true;
                        return true;
                    }
                );
                pit(
                    `commits all staged permission grants after delay`,
                    { numRuns: RUNS.verylow },
                    tuple(address, address).filter(
                        ([x, y]) =>
                            x !== y &&
                            x !== ethers.constants.AddressZero &&
                            y !== ethers.constants.AddressZero
                    ),
                    tuple(uint256, uint256).filter(
                        ([x, y]) => !x.or(y).eq(x) && x.gt(0)
                    ),
                    async (
                        [targetAddress, anotherTargetAddress]: [string, string],
                        [permissionMask, anotherPermissionMask]: [
                            BigNumber,
                            BigNumber
                        ]
                    ) => {
                        let permissionIds = permissionIdsByMask(permissionMask);
                        let anotherPermissionIds = permissionIdsByMask(
                            anotherPermissionMask
                        );
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                targetAddress,
                                permissionIds
                            );
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                anotherTargetAddress,
                                anotherPermissionIds
                            );
                        await this.subject
                            .connect(this.admin)
                            .commitAllPermissionGrantsSurpassedDelay();
                        expect(
                            await this.subject.hasAllPermissions(
                                targetAddress,
                                permissionIds
                            )
                        ).to.be.true;
                        expect(
                            await this.subject.hasAllPermissions(
                                anotherTargetAddress,
                                anotherPermissionIds
                            )
                        ).to.be.false;
                        return true;
                    }
                );
            });

            describe("edge cases", () => {
                describe("when attempting to commit a single permission too early", () => {
                    it("does not commit permission", async () => {
                        let targetAddress = randomAddress();
                        let permissionIds = permissionIdsByMask(
                            generateSingleParams(uint256.filter((x) => x.gt(0)))
                        );

                        await this.subject
                            .connect(this.admin)
                            .stagePermissionGrants(
                                targetAddress,
                                permissionIds
                            );
                        await sleep(this.governanceDelay - 10);
                        await this.subject
                            .connect(this.admin)
                            .commitAllPermissionGrantsSurpassedDelay();
                        expect(
                            await this.subject.hasAllPermissions(
                                targetAddress,
                                permissionIds
                            )
                        ).to.be.false;
                    });
                });
                describe("when attempting to commit multiple permissions too early", () => {
                    it(`does not commit these permissions`, async () => {
                        let targetAddresses = [];
                        let permissions = [];
                        const len = 10;
                        let randomIndex = randomInt(0, len - 1);
                        for (let i = 0; i < len; ++i) {
                            let targetAddress = randomAddress();
                            let permissionIds = permissionIdsByMask(
                                generateSingleParams(
                                    uint256.filter((x) => x.gt(0))
                                )
                            );
                            targetAddresses.push(targetAddress);
                            permissions.push(permissionIds);
                        }
                        for (let i = 0; i < randomIndex; ++i) {
                            await this.subject
                                .connect(this.admin)
                                .stagePermissionGrants(
                                    targetAddresses[i],
                                    permissions[i]
                                );
                        }
                        await sleep(this.governanceDelay);
                        for (
                            let i = randomIndex;
                            i < targetAddresses.length;
                            ++i
                        ) {
                            await this.subject
                                .connect(this.admin)
                                .stagePermissionGrants(
                                    targetAddresses[i],
                                    permissions[i]
                                );
                        }
                        await sleep(this.governanceDelay / 2);
                        await this.subject
                            .connect(this.admin)
                            .commitAllPermissionGrantsSurpassedDelay();

                        for (let i = 0; i < randomIndex; ++i) {
                            expect(
                                await this.subject.hasAllPermissions(
                                    targetAddresses[i],
                                    permissions[i]
                                )
                            ).to.be.true;
                        }
                        for (
                            let i = randomIndex;
                            i < targetAddresses.length;
                            ++i
                        ) {
                            expect(
                                await this.subject.hasAllPermissions(
                                    targetAddresses[i],
                                    permissions[i]
                                )
                            ).to.be.false;
                        }
                        return true;
                    });
                });
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitAllPermissionGrantsSurpassedDelay()
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .commitAllPermissionGrantsSurpassedDelay()
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .commitAllPermissionGrantsSurpassedDelay()
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });

        describe("#commitAllValidatorsSurpassedDelay", () => {
            it("emits ValidatorCommitted event", async () => {
                let targetAddress = randomAddress();
                let validatorAddress = randomAddress();
                await this.subject
                    .connect(this.admin)
                    .stageValidator(targetAddress, validatorAddress);
                await sleep(await this.subject.governanceDelay());
                await expect(
                    this.subject
                        .connect(this.admin)
                        .commitAllValidatorsSurpassedDelay()
                ).to.emit(this.subject, "ValidatorCommitted");
                return true;
            });

            describe("properties", () => {
                pit(
                    `commits all staged validators`,
                    { numRuns: RUNS.verylow },
                    tuple(address, address).filter(
                        ([x, y]) =>
                            x !== y &&
                            x !== ethers.constants.AddressZero &&
                            y !== ethers.constants.AddressZero
                    ),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    address.filter((x) => x !== ethers.constants.AddressZero),
                    async (
                        [targetAddress, anotherTargetAddress]: [string, string],
                        validatorAddress: string,
                        anotherValidatorAddress: string
                    ) => {
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(targetAddress, validatorAddress);
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(
                                anotherTargetAddress,
                                anotherValidatorAddress
                            );
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitAllValidatorsSurpassedDelay();
                        expect(
                            await this.subject.validatorsAddresses()
                        ).to.contain(targetAddress);
                        expect(
                            await this.subject.validatorsAddresses()
                        ).to.contain(anotherTargetAddress);
                        return true;
                    }
                );
                pit(
                    `commits all staged validators after delay`,
                    { numRuns: RUNS.verylow },
                    tuple(address, address).filter(
                        ([x, y]) =>
                            x !== y &&
                            x !== ethers.constants.AddressZero &&
                            y !== ethers.constants.AddressZero
                    ),
                    async ([targetAddress, anotherTargetAddress]: [
                        string,
                        string
                    ]) => {
                        while (
                            (await this.subject.validatorsAddresses()).includes(
                                targetAddress
                            )
                        ) {
                            targetAddress = randomAddress();
                        }
                        while (
                            (await this.subject.validatorsAddresses()).includes(
                                anotherTargetAddress
                            )
                        ) {
                            anotherTargetAddress = randomAddress();
                        }
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .commitAllValidatorsSurpassedDelay();
                        await expect(
                            await this.subject.stagedValidatorsAddresses()
                        ).to.be.empty;
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(targetAddress, randomAddress());
                        await sleep(await this.subject.governanceDelay());
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(
                                anotherTargetAddress,
                                randomAddress()
                            );
                        await this.subject
                            .connect(this.admin)
                            .commitAllValidatorsSurpassedDelay();
                        expect(
                            await this.subject.validatorsAddresses()
                        ).to.contain(targetAddress);
                        expect(
                            await this.subject.validatorsAddresses()
                        ).to.not.contain(anotherTargetAddress);
                        return true;
                    }
                );
            });

            describe("edge cases", () => {
                describe("when attempting to commit a single validator too early", () => {
                    it(`does not commit validator`, async () => {
                        let targetAddress = randomAddress();
                        let validatorAddress = randomAddress();
                        await this.subject
                            .connect(this.admin)
                            .stageValidator(targetAddress, validatorAddress);
                        await sleep(1);
                        await this.subject
                            .connect(this.admin)
                            .commitAllValidatorsSurpassedDelay();
                        expect(
                            await this.subject.validatorsAddresses()
                        ).to.not.contain(validatorAddress);
                        return true;
                    });
                });

                describe("when attempting to commit multiple validators too early", () => {
                    it(`does not commit these validators`, async () => {
                        let targetAddresses: Address[] = [];
                        const len = 10;
                        let randomIndex = randomInt(0, len - 1);
                        for (let i = 0; i < randomIndex; ++i) {
                            let targetAddress = randomAddress();
                            let validatorAddress = randomAddress();
                            await this.subject
                                .connect(this.admin)
                                .stageValidator(
                                    targetAddress,
                                    validatorAddress
                                );
                            targetAddresses.push(targetAddress);
                        }
                        await sleep(this.governanceDelay);
                        for (let i = randomIndex; i < len; ++i) {
                            let targetAddress = randomAddress();
                            let validatorAddress = randomAddress();
                            await this.subject
                                .connect(this.admin)
                                .stageValidator(
                                    targetAddress,
                                    validatorAddress
                                );
                            targetAddresses.push(targetAddress);
                        }
                        await sleep(this.governanceDelay / 2);
                        await this.subject
                            .connect(this.admin)
                            .commitAllValidatorsSurpassedDelay();
                        for (let i = 0; i < randomIndex; ++i) {
                            expect(
                                await this.subject.validatorsAddresses()
                            ).to.contain(targetAddresses[i]);
                        }
                        for (let i = randomIndex; i < len; ++i) {
                            expect(
                                await this.subject.validatorsAddresses()
                            ).to.not.contain(targetAddresses[i]);
                        }
                        return true;
                    });
                });
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitAllValidatorsSurpassedDelay()
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .commitAllValidatorsSurpassedDelay()
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .commitAllValidatorsSurpassedDelay()
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                    return true;
                });
            });
        });

        describe("#revokePermissions", () => {
            it("emits PermissionRevoked event", async () => {
                let targetAddress = randomAddress();
                let permissionIds = permissionIdsByMask(
                    generateSingleParams(uint256.filter((x) => x.gt(0)))
                );
                await this.subject
                    .connect(this.admin)
                    .stagePermissionGrants(targetAddress, permissionIds);
                await sleep(await this.subject.governanceDelay());
                await this.subject
                    .connect(this.admin)
                    .commitPermissionGrants(targetAddress);
                await expect(
                    this.subject
                        .connect(this.admin)
                        .revokePermissions(targetAddress, permissionIds)
                ).to.emit(this.subject, "PermissionsRevoked");
                return true;
            });
            describe("edge cases", () => {
                describe("when attempting to revoke from zero address", () => {
                    it(`reverts with ${Exceptions.NULL}`, async () => {
                        let permissionIds = permissionIdsByMask(
                            generateSingleParams(uint256.filter((x) => x.gt(0)))
                        );
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .revokePermissions(
                                    ethers.constants.AddressZero,
                                    permissionIds
                                )
                        ).to.be.revertedWith(Exceptions.NULL);
                        return true;
                    });
                });
            });
        });

        describe("#revokeValidator", () => {
            it("emits ValidatorRevoked event", async () => {
                let targetAddress = randomAddress();
                let validatorAddress = randomAddress();
                await this.subject
                    .connect(this.admin)
                    .stageValidator(targetAddress, validatorAddress);
                await sleep(await this.subject.governanceDelay());
                await this.subject
                    .connect(this.admin)
                    .commitValidator(targetAddress);
                await expect(
                    this.subject
                        .connect(this.admin)
                        .revokeValidator(targetAddress)
                ).to.emit(this.subject, "ValidatorRevoked");
                return true;
            });

            describe("edge cases", () => {
                describe("when attempting to revoke from zero address", () => {
                    it(`reverts with ${Exceptions.NULL}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .revokeValidator(ethers.constants.AddressZero)
                        ).to.be.revertedWith(Exceptions.NULL);
                        return true;
                    });
                });
            });
        });

        describe("#commitParams", () => {
            it("emits ParamsCommitted event", async () => {
                await this.subject
                    .connect(this.admin)
                    .stageParams(generateSingleParams(paramsArb));
                await sleep(await this.subject.governanceDelay());
                await expect(
                    this.subject.connect(this.admin).commitParams()
                ).to.emit(this.subject, "ParamsCommitted");
                return true;
            });

            describe("edge cases", () => {
                describe("when attempting to commit params too early", () => {
                    it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                        await this.subject
                            .connect(this.admin)
                            .stageParams(generateSingleParams(paramsArb));
                        await sleep(1);
                        await expect(
                            this.subject.connect(this.admin).commitParams()
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                        return true;
                    });
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
            it("emits PermissionGrantsStaged event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .stagePermissionGrants(
                            randomAddress(),
                            permissionIdsByMask(
                                generateSingleParams(
                                    uint256.filter((x) => x.gt(0))
                                )
                            )
                        )
                ).to.emit(this.subject, "PermissionGrantsStaged");
                return true;
            });

            describe("edge cases", () => {
                describe("when attempting to stage grant to zero address", () => {
                    it(`reverts with ${Exceptions.NULL}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stagePermissionGrants(
                                    ethers.constants.AddressZero,
                                    permissionIdsByMask(
                                        generateSingleParams(
                                            uint256.filter((x) => x.gt(0))
                                        )
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.NULL);
                        return true;
                    });
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

        describe("#stageValidator", () => {
            it("emits ValidatorStaged event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .stageValidator(randomAddress(), randomAddress())
                ).to.emit(this.subject, "ValidatorStaged");
                return true;
            });

            describe("edge cases", () => {
                describe("when attempting to stage grant to zero address", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO} when target has zero address`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageValidator(
                                    ethers.constants.AddressZero,
                                    randomAddress()
                                )
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                        return true;
                    });
                    it(`reverts with ${Exceptions.ADDRESS_ZERO} when validator has zero address`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageValidator(
                                    randomAddress(),
                                    ethers.constants.AddressZero
                                )
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                        return true;
                    });
                });
            });

            describe("access control", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageValidator(randomAddress(), randomAddress())
                    ).to.not.be.reverted;
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .stageValidator(randomAddress(), randomAddress())
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stageValidator(
                                    randomAddress(),
                                    randomAddress()
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#stageParams", () => {
            it("emits ParamsStaged event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .stageParams(generateSingleParams(paramsArb))
                ).to.emit(this.subject, "ParamsStaged");
                return true;
            });

            describe("edge cases", () => {
                describe("when given invalid params", () => {
                    describe("when maxTokensPerVault is zero", () => {
                        it(`reverts with ${Exceptions.NULL}`, async () => {
                            let params = generateSingleParams(paramsArb);
                            params.maxTokensPerVault = BigNumber.from(0);
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .stageParams(params)
                            ).to.be.revertedWith(Exceptions.NULL);
                            return true;
                        });
                    });

                    describe("when governanceDelay is zero", () => {
                        it(`reverts with ${Exceptions.NULL}`, async () => {
                            let params = generateSingleParams(paramsArb);
                            params.governanceDelay = BigNumber.from(0);
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .stageParams(params)
                            ).to.be.revertedWith(Exceptions.NULL);
                            return true;
                        });
                    });

                    describe("when governanceDelay exceeds MAX_GOVERNANCE_DELAY", () => {
                        it(`reverts with ${Exceptions.LIMIT_OVERFLOW}`, async () => {
                            let params = generateSingleParams(paramsArb);
                            params.governanceDelay = BigNumber.from(
                                MAX_GOVERNANCE_DELAY.add(1)
                            );
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .stageParams(params)
                            ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                            return true;
                        });
                    });

                    describe("when withdrawLimit less than MIN_WITHDRAW_LIMIT", () => {
                        it(`reverts with ${Exceptions.LIMIT_OVERFLOW}`, async () => {
                            let params = generateSingleParams(paramsArb);
                            params.withdrawLimit = BigNumber.from(
                                MIN_WITHDRAW_LIMIT.sub(1)
                            );
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .stageParams(params)
                            ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                            return true;
                        });
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
