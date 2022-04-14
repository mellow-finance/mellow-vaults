import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    randomAddress,
    withSigner,
    generateSingleParams,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { AllowAllValidator } from "./types";
import { ValidatorBehaviour } from "./behaviors/validator";
import { randomBytes } from "crypto";
import { uint256 } from "./library/property";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";

type CustomContext = {};

type DeployOptions = {};

contract<AllowAllValidator, DeployOptions, CustomContext>(
    "AllowAllValidator",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { address } = await deployments.get(
                        "AllowAllValidator"
                    );
                    this.subject = await ethers.getContractAt(
                        "AllowAllValidator",
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
                                randomBytes(4),
                                randomBytes(32)
                            )
                    ).to.not.be.reverted;
                });
            });
        });

        ValidatorBehaviour.call(this, {});
        ContractMetaBehaviour.call(this, {
            contractName: "AllowAllValidator",
            contractVersion: "1.0.0",
        });
    }
);
