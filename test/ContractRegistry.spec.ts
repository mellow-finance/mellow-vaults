import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { ContractRegistry } from "./types/ContractRegistry";
import { contract } from "./library/setup";

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
            it("registeres IContractMeta compatible contract", async () => {
                const vaultRegistry = await deployments.get("VaultRegistry");
                await expect(
                    this.subject.registerContract(vaultRegistry.address)
                ).to.not.be.reverted;
                let [semver, addr] = await this.subject.latestVersion(
                    ethers.utils.formatBytes32String("VaultRegistry")
                );
                semver = ethers.utils.parseBytes32String(semver);
                expect(semver).to.eq("1.0.0");
                expect(addr).to.eq(vaultRegistry.address);
                expect(
                    (await this.subject.names()).map((x) =>
                        ethers.utils.parseBytes32String(x)
                    )
                ).to.deep.eq(["VaultRegistry"]);
                expect(await this.subject.addresses()).to.deep.eq([
                    vaultRegistry.address,
                ]);
            });
        });
    }
);
