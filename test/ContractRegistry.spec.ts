import { expect } from "chai";
import { ethers, deployments, network } from "hardhat";
import { ContractRegistry } from "./types/ContractRegistry";
import { uint8, pit, RUNS } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { contract } from "./library/setup";
import { hexaString } from "fast-check";
import Exceptions from "./library/Exceptions";
import {
    withSigner,
    randomAddress,
    generateSingleParams,
    addSigner,
} from "./library/Helpers";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";

type CustomContext = {};
type DeployOptions = {};

contract<ContractRegistry, DeployOptions, CustomContext>(
    "ContractRegistry",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();

                    const governance = await deployments.get(
                        "ProtocolGovernance"
                    );
                    const factory = await ethers.getContractFactory(
                        "ContractRegistry"
                    );
                    this.subject = (await factory.deploy(
                        governance.address
                    )) as ContractRegistry;
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#registerContract", () => {
            it(`registers IContractMeta compatible contract and updates respective view methods
                - #addresses
                - #versions
                - #names
                - #latestVersion
                - #versionAddress`, async () => {
                const n1 = generateSingleParams(
                    uint8.filter((x) => x.gte(0) && x.lte(1))
                );
                const n2 = generateSingleParams(uint8.filter((x) => x.lt(20)));
                const n3 = generateSingleParams(uint8.filter((x) => x.lt(20)));
                const name = generateSingleParams(
                    hexaString({ minLength: 5, maxLength: 20 })
                );

                const semver = `${n1}.${n2}.${n3}`;
                const mockFactory = await ethers.getContractFactory(
                    "ContractMetaMock"
                );
                const mock = await mockFactory.deploy(name, semver);
                await expect(
                    this.subject.registerContract(mock.address)
                ).to.emit(this.subject, "ContractRegistered");
                const [semverResponse, addressResponse] =
                    await this.subject.latestVersion(name);
                expect(semverResponse).to.eq(semver);
                expect(addressResponse).to.eq(mock.address);
                expect(await this.subject.names()).to.contain(name);
                expect(await this.subject.addresses()).to.contain(mock.address);
                expect(await this.subject.versions(name)).to.have.members([
                    semverResponse,
                ]);
                expect(await this.subject.versionAddress(name, semver)).to.eq(
                    mock.address
                );
                return true;
            });

            describe("edge cases", () => {
                describe("when new contract major version differs more, than on one", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        // initial version
                        const semver = "1.0.0";
                        const name = "ContractMetaMock";
                        const mockFactory = await ethers.getContractFactory(
                            "ContractMetaMock"
                        );
                        const mock = await mockFactory.deploy(name, semver);
                        await this.subject.registerContract(mock.address);

                        const lowerSemver = "3.0.0";
                        const anotherMock = await mockFactory.deploy(
                            name,
                            lowerSemver
                        );
                        await expect(
                            this.subject.registerContract(anotherMock.address)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when new contract version lower or equal existing one", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        // initial version
                        const semver = "1.0.1";
                        const name = "ContractMetaMock";
                        const mockFactory = await ethers.getContractFactory(
                            "ContractMetaMock"
                        );
                        const mock = await mockFactory.deploy(name, semver);
                        await this.subject.registerContract(mock.address);

                        // lower version
                        const lowerSemver = "1.0.0";
                        const anotherMock = await mockFactory.deploy(
                            name,
                            lowerSemver
                        );
                        await expect(
                            this.subject.registerContract(anotherMock.address)
                        ).to.be.revertedWith(Exceptions.INVARIANT);

                        // equal version
                        const yetAnotherMock = await mockFactory.deploy(
                            name,
                            semver
                        );
                        await expect(
                            this.subject.registerContract(
                                yetAnotherMock.address
                            )
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });

                describe("when contract has invalid version", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        const semver = "1...";
                        const name = "ContractMetaMock";
                        const mockFactory = await ethers.getContractFactory(
                            "ContractMetaMock"
                        );
                        const mock = await mockFactory.deploy(name, semver);
                        await expect(
                            this.subject.registerContract(mock.address)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });

                describe("when contract name is not alphanumeric", () => {
                    it(`reverts with ${Exceptions.INVALID_VALUE}`, async () => {
                        const semver = "4.2.0";
                        const name = "¯\\_(ツ)_/¯";
                        const mockFactory = await ethers.getContractFactory(
                            "ContractMetaMock"
                        );
                        const mock = await mockFactory.deploy(name, semver);
                        await expect(
                            this.subject.registerContract(mock.address)
                        ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                    });
                });

                describe("when address is already registered", () => {
                    it(`reverts with ${Exceptions.DUPLICATE}`, async () => {
                        const semver = "1.0.0";
                        const name = "ContractMetaMock";
                        const mockFactory = await ethers.getContractFactory(
                            "ContractMetaMock"
                        );
                        const mock = await mockFactory.deploy(name, semver);
                        await this.subject.registerContract(mock.address);
                        await expect(
                            this.subject.registerContract(mock.address)
                        ).to.be.revertedWith(Exceptions.DUPLICATE);
                    });
                });
            });

            describe("access control", () => {
                it("allowed: operator (deployer)", async () => {
                    const semver = "1.0.1";
                    const name = "Random";
                    const mockFactory = await ethers.getContractFactory(
                        "ContractMetaMock"
                    );

                    const mock = await mockFactory.deploy(name, semver);
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .registerContract(mock.address)
                    ).to.not.be.reverted;
                });
                it(`denied with ${Exceptions.FORBIDDEN}: random address`, async () => {
                    const semver = "1.0.1";
                    const name = "Random";
                    const mockFactory = await ethers.getContractFactory(
                        "ContractMetaMock"
                    );

                    var signer = await addSigner(randomAddress());
                    const mock = await mockFactory.deploy(name, semver);
                    await expect(
                        this.subject
                            .connect(signer)
                            .registerContract(mock.address)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("allowed: protocol admin", async () => {
                    const semver = "1.0.1";
                    const name = "Admin";
                    const mockFactory = await ethers.getContractFactory(
                        "ContractMetaMock"
                    );
                    const mock = await mockFactory.deploy(name, semver);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .registerContract(mock.address)
                    ).to.not.be.reverted;
                });
            });
        });

        ContractMetaBehaviour.call(this, {
            contractName: "ContractRegistry",
            contractVersion: "1.0.0",
        });
    }
);
