import { ethers, deployments } from "hardhat";
import { encodeToBytes } from "../library/Helpers";
import { contract } from "../library/setup";
import { expect } from "chai";
import { BatchCall } from "../types";

import Exceptions from "../library/Exceptions";

type CustomContext = {};

type DeployOptions = {};

contract<BatchCall, DeployOptions, CustomContext>("BatchCall", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                this.subject = await ethers.getContract("BatchCall");
                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#batchcall", () => {
        it("returns results", async () => {
            await expect(this.subject.batchcall([], [])).not.to.be.reverted;
        });

        describe("edge cases:", () => {
            describe("when arrays have different lengths", () => {
                it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                    await expect(
                        this.subject.batchcall([this.usdc.address], [])
                    ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                });
            });

            describe("when targets arrays not only of contracts", () => {
                it(`reverts with "Address: call to non-contract"`, async () => {
                    var data = encodeToBytes(["bytes"], [0]);
                    await expect(
                        this.subject.batchcall(
                            [ethers.constants.AddressZero],
                            [data]
                        )
                    ).to.be.revertedWith(
                        "Address: call to non-contract"
                    );
                });
            });
        });
    });
});
