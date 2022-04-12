import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";
import {
    randomAddress,
    withSigner,
    generateSingleParams,
    sortBigNumbers,
    sortAddresses,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { CommonTest } from "./types";
import { ValidatorBehaviour } from "./behaviors/validator";
import { randomBytes, randomInt } from "crypto";
import { uint256 } from "./library/property";
import { deployCommonLibraryTest } from "./library/Deployments";
import { BigNumber } from "ethers";

type CustomContext = {};

type DeployOptions = {};

contract<CommonTest, DeployOptions, CustomContext>("CommonTest", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                let { address } = await deployCommonLibraryTest();
                this.subject = await ethers.getContractAt(
                    "CommonTest",
                    address
                );
                return this.subject;
            }
        );
    });

    function genProjectTokenAmount(
        uniqueTokensLen: number,
        uniqueProjectTokensLen: number,
        sharedTokensLen: number,
        shouldRevert: boolean
    ) {
        let uniqueTokens = [...Array(uniqueTokensLen).keys()].map((d) => {
            return randomAddress();
        });
        let uniqueProjectTokens = [...Array(uniqueProjectTokensLen).keys()].map(
            (d) => {
                return randomAddress();
            }
        );
        let sharedTokens = [...Array(sharedTokensLen).keys()].map((d) => {
            return randomAddress();
        });
        let tokens = sortAddresses(uniqueTokens.concat(sharedTokens));
        let tokensToProject = sortAddresses(
            uniqueProjectTokens.concat(sharedTokens)
        );
        let tokenAmountsToProject = [...tokensToProject.values()].map(
            (projectToken) => {
                if (sharedTokens.includes(projectToken)) {
                    return generateSingleParams(uint256);
                } else {
                    return shouldRevert ? generateSingleParams(uint256) : BigNumber.from(0);
                }
            }
        );
        let result = [...tokens.values()].map(
            (token) => {
                return tokensToProject.includes(token)
                    ? tokenAmountsToProject[tokensToProject.indexOf(token)]
                    : BigNumber.from(0)
            }
        );
        return Object({ tokens, tokensToProject, tokenAmountsToProject, result});
    }

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#sortUint", () => {
        it("sort unsorted", async () => {
            let unsorted = [...Array(randomInt(3, 10)).keys()].map((d) => {
                return generateSingleParams(uint256);
            });
            await expect(await this.subject.sortUint(unsorted)).to.deep.equal(
                sortBigNumbers(unsorted)
            );
        });
        it("sort empty", async () => {
            let unsorted: BigNumber[] = [];
            await expect(await this.subject.sortUint(unsorted)).to.deep.equal(
                sortBigNumbers(unsorted)
            );
        });

        it("sort non-unique", async () => {
            let unsorted = [...Array(randomInt(3, 10)).keys()].map((d) => {
                return generateSingleParams(uint256);
            });
            let unsorted_doubled = unsorted.concat(unsorted);
            await expect(
                await this.subject.sortUint(unsorted_doubled)
            ).to.deep.equal(sortBigNumbers(unsorted_doubled));
        });
    });

    describe("#projectTokenAmounts", () => {
        it("succesfull, tokens is subset of tokensToProject", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(0, randomInt(1, 10), randomInt(0, 10), false);
            await expect(
                await this.subject.projectTokenAmountsTest(
                    tokens,
                    tokensToProject,
                    tokenAmountsToProject
                )
            ).to.be.deep.eq(result);
        });

        it("succesfull, tokens is superset of tokensToProject", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(1, 0, 0, false);
            let res = await this.subject.projectTokenAmountsTest(
                tokens,
                tokensToProject,
                tokenAmountsToProject
            );
            console.log(res)
            console.log(result)
            for (let i = 0; i < res.length; i++) {
                if (!res[i].eq(result[i])) {
                    console.log("OMG");
                }
            }
            await expect(
                res
            ).to.deep.eq(result);
        });

        it("succesfull, tokens and tokensToProject are the same", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(0, 0, randomInt(1, 10), false);
            await expect(
                await this.subject.projectTokenAmountsTest(
                    tokens,
                    tokensToProject,
                    tokenAmountsToProject
                )
            ).to.be.deep.eq(result);
        });

        it("succesfull, tokens and tokensToProject diverge a lot", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(randomInt(1, 10), randomInt(1, 10), randomInt(1, 10), false);
            await expect(
                await this.subject.projectTokenAmountsTest(
                    tokens,
                    tokensToProject,
                    tokenAmountsToProject
                )
            ).to.be.deep.eq(result);
        });

        it("succesfull, tokens and tokensToProject share no tokens", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(randomInt(1, 10), randomInt(1, 10), 0, false);
            await expect(
                await this.subject.projectTokenAmountsTest(
                    tokens,
                    tokensToProject,
                    tokenAmountsToProject
                )
            ).to.be.deep.eq(result);
        });

        describe("edge cases:", () => {
            describe("when projecting token doesnt exist in tokens and his amount is not zero", () => {
                it("reverts with TPS", async () => {
                    const { tokens, tokensToProject, tokenAmountsToProject } =
                        genProjectTokenAmount(randomInt(0, 10), randomInt(1, 10), randomInt(0, 10), true);
                    await expect(
                        this.subject.projectTokenAmountsTest(
                            tokens,
                            tokensToProject,
                            tokenAmountsToProject
                        )
                    ).to.be.revertedWith("TPS");
                });
            });
        });
    });
});
