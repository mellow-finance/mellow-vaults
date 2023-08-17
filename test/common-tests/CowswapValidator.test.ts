import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    generateSingleParams,
    randomAddress,
    withSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { CowswapValidator } from "../types";
import { ValidatorBehaviour } from "../behaviors/validator";
import Exceptions from "../library/Exceptions";
import { randomBytes } from "crypto";
import { uint256 } from "../library/property";
import { ContractMetaBehaviour } from "../behaviors/contractMeta";

type CustomContext = {};

type DeployOptions = {};

contract<CowswapValidator, DeployOptions, CustomContext>(
    "CowswapValidator",
    function () {
        const PRE_SIGNATURE_SELECTOR = "0xec6cb13f";

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { address } = await deployments.get(
                        "CowswapValidator"
                    );
                    this.subject = await ethers.getContractAt(
                        "CowswapValidator",
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
            it("successful validate", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                randomAddress(),
                                randomAddress(),
                                generateSingleParams(uint256),
                                PRE_SIGNATURE_SELECTOR,
                                randomBytes(32)
                            )
                    ).to.not.be.reverted;
                });
            });
            describe("edge cases:", async () => {
                describe(`when selector is not ${PRE_SIGNATURE_SELECTOR}`, async () => {
                    it(`reverts with ${Exceptions.INVALID_SELECTOR}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        randomAddress(),
                                        randomAddress(),
                                        generateSingleParams(uint256),
                                        randomBytes(4),
                                        randomBytes(32)
                                    )
                            ).to.be.revertedWith(Exceptions.INVALID_SELECTOR);
                        });
                    });
                });
            });
        });

        ValidatorBehaviour.call(this, {});
        ContractMetaBehaviour.call(this, {
            contractName: "CowswapValidator",
            contractVersion: "1.0.0",
        });
    }
);
