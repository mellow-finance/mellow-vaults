import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { arrayify } from "@ethersproject/bytes";
import { SemverLibraryTest } from "./types/SemverLibraryTest";
import { uint256, uint8, pit, RUNS } from "./library/property";
import { contract } from "./library/setup";
import { generateSingleParams } from "./library/Helpers";

type CustomContext = {};
type DeployOptions = {};

contract<SemverLibraryTest, DeployOptions, CustomContext>(
    "SemverLibraryTest",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();

                    const factory = await ethers.getContractFactory(
                        "SemverLibraryTest"
                    );
                    this.subject =
                        (await factory.deploy()) as SemverLibraryTest;
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        pit(
            "(stringifySemver o numberifySemver)(x) = x",
            { numRuns: RUNS.low },
            uint8.filter((x) => x.gt(0) && x.lt(20)),
            uint8.filter((x) => x.lt(20)),
            uint8.filter((x) => x.lt(20)),
            async (n1: BigNumber, n2: BigNumber, n3: BigNumber) => {
                const semver = `${n1}.${n2}.${n3}`;
                const numberified = await this.subject.numberifySemver(semver);
                const stringified = await this.subject.stringifySemver(
                    numberified
                );
                expect(stringified).to.eq(semver);
                return true;
            }
        );

        describe("#stringifySemver", () => {
            it("succesful stringify", async () => {
                let number = generateSingleParams(uint256).mod(
                    BigNumber.from(2).pow(24)
                );
                let major = number.div(BigNumber.from(2).pow(16));
                let minor = number
                    .div(BigNumber.from(2).pow(8))
                    .mod(BigNumber.from(2).pow(8));
                let patch = number.mod(BigNumber.from(2).pow(8));
                expect(await this.subject.stringifySemver(number)).to.be.eq(
                    `${major}.${minor}.${patch}`
                );
            });
            describe("edge cases", () => {
                describe("when num is too large", () => {
                    it('returns "0"', async () => {
                        expect(
                            await this.subject.stringifySemver(
                                generateSingleParams(uint256).add(
                                    BigNumber.from(2).pow(24)
                                )
                            )
                        ).to.be.eq("0");
                    });
                });
            });
        });

        describe("#numberifySemver", () => {
            describe("edge cases", () => {
                it("returns zero on '0.0.0'", async () => {
                    const semver = "0.0.0";
                    const input = ethers.utils.formatBytes32String(semver);
                    const numberified = await this.subject.numberifySemver(
                        input
                    );
                    expect(numberified).to.eq(BigNumber.from(0));
                });
                it("returns zero on '4.2'", async () => {
                    const semver = "4.2";
                    const input = ethers.utils.formatBytes32String(semver);
                    const numberified = await this.subject.numberifySemver(
                        input
                    );
                    expect(numberified).to.eq(BigNumber.from(0));
                });
                it("returns zero on '42'", async () => {
                    const semver = "42";
                    const numberified = await this.subject.numberifySemver(
                        semver
                    );
                    expect(numberified).to.eq(BigNumber.from(0));
                });
                it("returns zero on '4..20'", async () => {
                    const semver = "4..20";
                    const numberified = await this.subject.numberifySemver(
                        semver
                    );
                    expect(numberified).to.eq(BigNumber.from(0));
                });
                it("returns '4.2.0' on '04.2.0'", async () => {
                    const semver = "04.2.0";
                    const numberified = await this.subject.numberifySemver(
                        semver
                    );
                    expect(numberified).to.eq(
                        BigNumber.from(4 * (1 << 16) + 2 * (1 << 8))
                    );
                });
                it("returns zero on '4:20", async () => {
                    const semver = "4:20";
                    const numberified = await this.subject.numberifySemver(
                        semver
                    );
                    expect(numberified).to.eq(BigNumber.from(0));
                });
                it("returns zero on '4.2.0.1'", async () => {
                    const semver = "4.2.0.1";
                    const numberified = await this.subject.numberifySemver(
                        semver
                    );
                    expect(numberified).to.eq(BigNumber.from(0));
                });
            });
        });
    }
);
