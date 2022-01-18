import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { arrayify } from "@ethersproject/bytes";
import { SemverLibraryTest } from "./types/SemverLibraryTest";
import { uint256, uint8, pit, RUNS } from "./library/property";
import { contract } from "./library/setup";

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
            "stringifySemver(numberifySemver(x)) == x",
            { numRuns: RUNS.low },
            uint8.filter((x) => x.gt(0) && x.lt(20)),
            uint8.filter((x) => x.lt(20)),
            uint8.filter((x) => x.lt(20)),
            async (n1: BigNumber, n2: BigNumber, n3: BigNumber) => {
                const semver = `${n1}.${n2}.${n3}`;
                const input = ethers.utils.formatBytes32String(semver);
                const numberified = await this.subject.numberifySemver(input);
                const stringifier = ethers.utils.parseBytes32String(
                    await this.subject.stringifySemver(numberified)
                );
                expect(stringifier).to.eq(semver);
                return true;
            }
        );

        describe("#numberify", () => {
            pit(
                "converts number to string",
                { numRuns: RUNS.low },
                uint256,
                async (a: BigNumber) => {
                    const input: number[] = a
                        .toString()
                        .split("")
                        .map((x) => x.charCodeAt(0));
                    const result: BigNumber = await this.subject.numberify(
                        input
                    );
                    expect(result).to.eq(a);
                    return true;
                }
            );
        });

        describe("#stringify", () => {
            pit(
                "converts string to number",
                { numRuns: RUNS.low },
                uint256,
                async (a: BigNumber) => {
                    const response = arrayify(await this.subject.stringify(a));
                    let result: string = "";
                    for (const i of response) {
                        result += String.fromCharCode(i);
                    }
                    expect(result).to.eq(a.toString());
                    return true;
                }
            );
        });
    }
);
