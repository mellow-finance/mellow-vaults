import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    encodeToBytes,
    randomAddress,
    sleep,
    withSigner,
    generateSingleParams,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20Validator } from "./types";
import { PermissionIdsLibrary } from "../deploy/0000_utils";
import { ValidatorBehaviour } from "./behaviors/validator";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";
import Exceptions from "./library/Exceptions";
import { randomBytes, randomInt } from "crypto";
import { uint256 } from "./library/property";

type CustomContext = {};

type DeployOptions = {};

contract<ERC20Validator, DeployOptions, CustomContext>(
    "ERC20Validator",
    function () {
        const APPROVE_SELECTOR = "0x095ea7b3";

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { address } = await deployments.get("ERC20Validator");
                    this.subject = await ethers.getContractAt(
                        "ERC20Validator",
                        address
                    );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#validate", () => {
            it("successful validate, spender can approve", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    let tokenAddress = randomAddress();
                    let spenderAddress = randomAddress();
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(tokenAddress, [
                            PermissionIdsLibrary.ERC20_TRANSFER,
                        ]);
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(spenderAddress, [
                            PermissionIdsLibrary.ERC20_APPROVE,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                signer.address,
                                tokenAddress,
                                0,
                                APPROVE_SELECTOR,
                                encodeToBytes(["address"], [spenderAddress])
                            )
                    ).to.not.be.reverted;
                });
            });

            it("successful validate, sender is trusted strategy", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    let tokenAddress = randomAddress();
                    let spenderAddress = randomAddress();
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(tokenAddress, [
                            PermissionIdsLibrary.ERC20_TRANSFER,
                        ]);
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(spenderAddress, [
                            PermissionIdsLibrary.ERC20_APPROVE_RESTRICTED,
                        ]);
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(signer.address, [
                            PermissionIdsLibrary.ERC20_TRUSTED_STRATEGY,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                signer.address,
                                tokenAddress,
                                0,
                                APPROVE_SELECTOR,
                                encodeToBytes(["address"], [spenderAddress])
                            )
                    ).to.not.be.reverted;
                });
            });

            describe("edge cases:", () => {
                describe("when value is not zero", () => {
                    it(`reverts with ${Exceptions.INVALID_VALUE}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        signer.address,
                                        randomAddress(),
                                        generateSingleParams(uint256),
                                        randomBytes(4),
                                        randomBytes(randomInt(32))
                                    )
                            ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                        });
                    });
                });

                describe(`when selector is not ${APPROVE_SELECTOR}`, () => {
                    it(`reverts with ${Exceptions.INVALID_SELECTOR}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        signer.address,
                                        randomAddress(),
                                        0,
                                        randomBytes(4),
                                        randomBytes(randomInt(32))
                                    )
                            ).to.be.revertedWith(Exceptions.INVALID_SELECTOR);
                        });
                    });
                });

                describe("when no transfer permission", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        signer.address,
                                        randomAddress(),
                                        0,
                                        APPROVE_SELECTOR,
                                        randomBytes(randomInt(32))
                                    )
                            ).to.be.revertedWith(Exceptions.FORBIDDEN);
                        });
                    });
                });

                describe("when no approve permission", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            let tokenAddress = randomAddress();
                            this.protocolGovernance
                                .connect(this.admin)
                                .stagePermissionGrants(tokenAddress, [
                                    PermissionIdsLibrary.ERC20_TRANSFER,
                                ]);
                            await sleep(
                                await this.protocolGovernance.governanceDelay()
                            );
                            this.protocolGovernance
                                .connect(this.admin)
                                .commitPermissionGrants(tokenAddress);
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        signer.address,
                                        tokenAddress,
                                        0,
                                        APPROVE_SELECTOR,
                                        randomBytes(32)
                                    )
                            ).to.be.revertedWith(Exceptions.FORBIDDEN);
                        });
                    });
                });
            });
        });

        ValidatorBehaviour.call(this, {});
        ContractMetaBehaviour.call(this, {
            contractName: "ERC20Validator",
            contractVersion: "1.0.0",
        });
    }
);
