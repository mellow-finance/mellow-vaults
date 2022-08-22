import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { ISqueethShortHelper, SqueethVault } from "./types";
import { contract } from "./library/setup";

type CustomContext = {};

type DeployOptions = {};

contract<SqueethVault, DeployOptions, CustomContext>(
    "SqueethVaultTest",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();

                    const factory = await ethers.getContractFactory(
                        "SqueethVault"
                    );
                    this.subject = await ethers.getContract("SqueethVault");
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        it("calls openPosition", async () => {
            await this.subject.openShortPosition();
        });
    }
);
