import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { contract } from "./library/setup";

import { AggregatorV3wstEth } from "./types";

type DeployOptions = {};
type CustomContext = {};

contract<AggregatorV3wstEth, DeployOptions, CustomContext>(
    "AggregatorV3wstEth",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { deploy } = deployments;
                    const { wsteth, chainlinkSteth } = await getNamedAccounts();
                    const deployParams = await deploy("AggregatorV3wstEth", {
                        from: this.deployer.address,
                        contract: "AggregatorV3wstEth",
                        args: [wsteth, chainlinkSteth],
                        log: true,
                        autoMine: true,
                    });
                    this.subject = await ethers.getContractAt(
                        "AggregatorV3wstEth",
                        deployParams.address
                    );

                    this.subjectPrice = async () => {
                        const decimals = await this.subject.decimals();
                        const { answer } = await this.subject.latestRoundData();
                        return { decimals, answer };
                    };

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#latestRoundData", () => {
            it("does not revert", async () => {
                await expect(this.subject.latestRoundData()).not.to.be.reverted;
            });

            it("calculates correctly", async () => {
                const subjectPrice = await this.subjectPrice();
                expect(subjectPrice.decimals).to.be.eq(8);
                expect(subjectPrice.answer.toNumber()).to.be.eq(114141987358);
            });
        });

        describe("#getRoundData", () => {
            it("always reverts", async () => {
                await expect(
                    this.subject.getRoundData(1000)
                ).to.be.revertedWith("DIS");
            });
        });
    }
);
