import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { contract } from "./library/setup";
import { UniV3Vault } from "./types/UniV3Vault";

type DeployContext = {};
type CustomContext = {};

contract<UniV3Vault, DeployContext, CustomContext>("UniV3Vault", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployContext) => {
                return this.subject;
            }
        );
    });

    beforeEach(async () => {});

    describe("#onERC721Received", () => {
        it("receives nft and updates tvl", async () => {});

        describe("edge cases", () => {
            describe("when already has nft", () => {
                describe("when has some assets", () => {
                    it("reverts", async () => {});
                });

                describe("when position is empty", () => {
                    it("replaces nft", async () => {});
                });
            });
        });
    });
});
