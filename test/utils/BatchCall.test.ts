import { ethers, deployments } from "hardhat";
import { encodeToBytes } from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { expect } from "chai";
import { BatchCall } from "../types";

import Exceptions from "../library/Exceptions";

type CustomContext = {
    batchCall: BatchCall;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "BatchCall",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    this.batchCall = await ethers.getContract("BatchCall");
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#batchcall", () => {
            it("returns results", async () => {
                await expect(this.batchCall.batchcall([], [])).not.to.be
                    .reverted;
            });

            describe("edge cases:", () => {
                describe("when arrays have different lengths", () => {
                    it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                        await expect(
                            this.batchCall.batchcall([this.usdc.address], [])
                        ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                    });
                });

                describe("when targets arrays not only of contracts", () => {
                    it(`reverts with "Address: delegate call to non-contract"`, async () => {
                        var data = encodeToBytes(["bytes"], [0]);
                        await expect(
                            this.batchCall.batchcall(
                                [ethers.constants.AddressZero],
                                [data]
                            )
                        ).to.be.revertedWith(
                            "Address: delegate call to non-contract"
                        );
                    });
                });
            });
        });
    }
);
