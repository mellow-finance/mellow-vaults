import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";
import {
    randomAddress,
    withSigner,
    generateSingleParams,
    sortBigNumbers,
    sortAddresses,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { CommonTest } from "../types";
import { ValidatorBehaviour } from "../behaviors/validator";
import { randomBytes, randomInt } from "crypto";
import { uint256 } from "../library/property";
import { deployCommonLibraryTest } from "../library/Deployments";
import { BigNumber } from "ethers";
import { ripemd160, sha512 } from "ethers/lib/utils";
import { toObject } from "../../deploy/0000_utils";
import Exceptions from "../library/Exceptions";
import exp from "constants";

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
                    return shouldRevert
                        ? generateSingleParams(uint256)
                        : BigNumber.from(0);
                }
            }
        );
        let result = [...tokens.values()].map((token) => {
            return tokensToProject.includes(token)
                ? tokenAmountsToProject[tokensToProject.indexOf(token)]
                : BigNumber.from(0);
        });
        return Object({
            tokens,
            tokensToProject,
            tokenAmountsToProject,
            result,
        });
    }

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#sortUint", () => {
        it("sort unsorted", async () => {
            let unsorted = [...Array(randomInt(3, 10)).keys()].map((d) => {
                return generateSingleParams(uint256);
            });
            expect(await this.subject.sortUint(unsorted)).to.deep.equal(
                sortBigNumbers(unsorted)
            );
        });
        it("sort empty", async () => {
            let unsorted: BigNumber[] = [];
            expect(await this.subject.sortUint(unsorted)).to.deep.equal(
                sortBigNumbers(unsorted)
            );
        });

        it("sort non-unique", async () => {
            let unsorted = [...Array(randomInt(3, 10)).keys()].map((d) => {
                return generateSingleParams(uint256);
            });
            let unsorted_doubled = unsorted.concat(unsorted);
            expect(await this.subject.sortUint(unsorted_doubled)).to.deep.equal(
                sortBigNumbers(unsorted_doubled)
            );
        });
    });

    describe("#isSortedAndUnique", () => {
        it("returns true when length less then 2", async () => {
            let tokens = [...Array(randomInt(0, 1)).keys()].map((v) =>
                randomAddress()
            );
            expect(await this.subject.isSortedAndUnique(tokens)).to.be.true;
        });
        it("returns true when sorted", async () => {
            let tokens = [...Array(randomInt(2, 10)).keys()].map((v) =>
                randomAddress()
            );
            tokens = sortAddresses(tokens);
            expect(await this.subject.isSortedAndUnique(tokens)).to.be.true;
        });
        it("returns false when unsorted", async () => {
            let tokens = [...Array(randomInt(2, 10)).keys()].map((v) =>
                randomAddress()
            );
            tokens = sortAddresses(tokens);
            let swap1 =
                tokens.length != 2 ? randomInt(0, tokens.length - 2) : 0;
            let swap2 =
                tokens.length != 2
                    ? randomInt(swap1 + 1, tokens.length - 1)
                    : 1;
            [tokens[swap1], tokens[swap2]] = [tokens[swap2], tokens[swap1]];
            expect(await this.subject.isSortedAndUnique(tokens)).to.be.false;
        });
    });

    describe("#projectTokenAmounts", () => {
        it("succesfull, tokens is subset of tokensToProject", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(
                    0,
                    randomInt(1, 10),
                    randomInt(0, 10),
                    false
                );
            expect(
                await this.subject.projectTokenAmounts(
                    tokens,
                    tokensToProject,
                    tokenAmountsToProject
                )
            ).to.be.equivalent(result);
        });

        it("succesfull, tokens is superset of tokensToProject", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(1, 0, 0, false);
            expect(
                await this.subject.projectTokenAmounts(
                    tokens,
                    tokensToProject,
                    tokenAmountsToProject
                )
            ).to.be.equivalent(result);
        });

        it("succesfull, tokens and tokensToProject are the same", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(0, 0, randomInt(1, 10), false);
            expect(
                await this.subject.projectTokenAmounts(
                    tokens,
                    tokensToProject,
                    tokenAmountsToProject
                )
            ).to.be.equivalent(result);
        });

        it("succesfull, tokens and tokensToProject diverge a lot", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(
                    randomInt(1, 10),
                    randomInt(1, 10),
                    randomInt(1, 10),
                    false
                );
            expect(
                await this.subject.projectTokenAmounts(
                    tokens,
                    tokensToProject,
                    tokenAmountsToProject
                )
            ).to.be.equivalent(result);
        });

        it("succesfull, tokens and tokensToProject share no tokens", async () => {
            const { tokens, tokensToProject, tokenAmountsToProject, result } =
                genProjectTokenAmount(
                    randomInt(1, 10),
                    randomInt(1, 10),
                    0,
                    false
                );
            expect(
                await this.subject.projectTokenAmounts(
                    tokens,
                    tokensToProject,
                    tokenAmountsToProject
                )
            ).to.be.equivalent(result);
        });

        describe("edge cases:", () => {
            describe("when projecting token doesnt exist in tokens and his amount is not zero", () => {
                it("reverts with TPS", async () => {
                    const { tokens, tokensToProject, tokenAmountsToProject } =
                        genProjectTokenAmount(
                            randomInt(0, 10),
                            randomInt(1, 10),
                            randomInt(0, 10),
                            true
                        );
                    expect(
                        this.subject.projectTokenAmounts(
                            tokens,
                            tokensToProject,
                            tokenAmountsToProject
                        )
                    ).to.be.revertedWith("TPS");
                });
            });
        });
    });

    function genBigNumberBetweenPowersOfTwo(a: number, b: number) {
        let x = generateSingleParams(uint256);
        let upperBound = BigNumber.from(2).pow(b);
        let lowerBound = BigNumber.from(2).pow(a);
        x = x.mod(upperBound);
        if (x.lt(lowerBound)) {
            x = x.add(lowerBound);
        }
        return x;
    }

    describe("#sqrtX96", () => {
        it("succesfull, x in [2 ** 128, 2 ** 256)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(128, 256);
            let sqrt = (await this.subject.sqrtX96(x)).div(
                BigNumber.from(2).pow(48)
            );
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 64, 2 ** 128)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(64, 128);
            let sqrt = (await this.subject.sqrtX96(x)).div(
                BigNumber.from(2).pow(48)
            );
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 32, 2 ** 64)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(32, 64);
            let sqrt = (await this.subject.sqrtX96(x)).div(
                BigNumber.from(2).pow(48)
            );
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 16, 2 ** 32)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(16, 32);
            let sqrt = (await this.subject.sqrtX96(x)).div(
                BigNumber.from(2).pow(48)
            );
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 8, 2 ** 16)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(8, 32);
            let sqrt = (await this.subject.sqrtX96(x)).div(
                BigNumber.from(2).pow(48)
            );
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 4, 2 ** 8)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(4, 8);
            let sqrt = (await this.subject.sqrtX96(x)).div(
                BigNumber.from(2).pow(48)
            );
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 3, 2 ** 4)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(3, 4);
            let sqrt = (await this.subject.sqrtX96(x)).div(
                BigNumber.from(2).pow(48)
            );
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [0, 2 ** 3)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(0, 3);
            let sqrt = (await this.subject.sqrtX96(x)).div(
                BigNumber.from(2).pow(48)
            );
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
    });

    describe("#sqrt", () => {
        it("succesfull, x in [2 ** 128, 2 ** 256)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(128, 256);
            let sqrt = await this.subject.sqrt(x);
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 64, 2 ** 128)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(64, 128);
            let sqrt = await this.subject.sqrt(x);
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 32, 2 ** 64)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(32, 64);
            let sqrt = await this.subject.sqrt(x);
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 16, 2 ** 32)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(16, 32);
            let sqrt = await this.subject.sqrt(x);
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 8, 2 ** 16)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(8, 32);
            let sqrt = await this.subject.sqrt(x);
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 4, 2 ** 8)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(4, 8);
            let sqrt = await this.subject.sqrt(x);
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [2 ** 3, 2 ** 4)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(3, 4);
            let sqrt = await this.subject.sqrt(x);
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
        it("succesfull, x in [0, 2 ** 3)", async () => {
            let x = genBigNumberBetweenPowersOfTwo(0, 3);
            let sqrt = await this.subject.sqrt(x);
            expect(sqrt.pow(2).lte(x)).to.be.true;
            expect(sqrt.add(1).pow(2).gt(x)).to.be.true;
        });
    });

    describe("#recoverSigner", () => {
        it("succesfull recover", async () => {
            const messageHash = ethers.utils
                .hashMessage(randomBytes(32).toString("hex"))
                .substr(2);

            const signature = await this.deployer.signMessage(messageHash);
            expect(
                await this.subject.recoverSigner(
                    ethers.utils.keccak256(
                        Array.from(
                            `\x19Ethereum Signed Message:\n${messageHash.length.toString()}${messageHash}`,
                            (x) => x.charCodeAt(0)
                        )
                    ),
                    signature
                )
            ).to.be.equal(this.deployer.address);
        });
        describe("edge cases:", () => {
            describe("when signature length is not 65", () => {
                it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                    let signatureLength = randomInt(128);
                    signatureLength =
                        signatureLength == 65 ? 64 : signatureLength;
                    expect(
                        this.subject.recoverSigner(
                            randomBytes(32),
                            randomBytes(signatureLength)
                        )
                    ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                });
            });
        });
    });

    describe("#splitSignature", () => {
        it("succesfull split", async () => {
            let r = randomBytes(32);
            let s = randomBytes(32);
            let v = randomBytes(1);
            let signature = Buffer.concat([r, s, v]);
            expect(
                toObject(await this.subject.splitSignature(signature))
            ).to.be.deep.eq({
                r: "0x" + r.toString("hex"),
                s: "0x" + s.toString("hex"),
                v: v.readUInt8(),
            });
        });
        describe("edge cases:", () => {
            describe("when signature length is not 65", () => {
                it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                    let signatureLength = randomInt(128);
                    signatureLength =
                        signatureLength == 65 ? 64 : signatureLength;
                    expect(
                        this.subject.splitSignature(
                            randomBytes(signatureLength)
                        )
                    ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                });
            });
        });
    });
});
