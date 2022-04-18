import hre from "hardhat";
import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { contract } from "../library/setup";

import { InterfaceMapper } from "../types";

type CustomContext = {};
type DeployOptions = {};

contract<InterfaceMapper, DeployOptions, CustomContext>(
    "InterfaceMapper",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __) => {
                    const { deployments, getNamedAccounts } = hre;
                    const { deploy } = deployments;
                    const { deployer } = await getNamedAccounts();

                    await deploy("InterfaceMapper", {
                        from: deployer,
                        args: [],
                        log: true,
                        autoMine: true,
                    });

                    this.subject = await ethers.getContract("InterfaceMapper");
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe.only("#constructor", () => {
            it("Check interface Ids", async () => {
                expect(await this.subject.ERC165_INTERFACE_ID()).to.not.eq(
                    "0x00000000"
                );

                expect(
                    await this.subject.CHAINLINK_ORACLE_INTERFACE_ID()
                ).to.not.eq("0x00000000");
                expect(
                    await this.subject.UNIV2_ORACLE_INTERFACE_ID()
                ).to.not.eq("0x00000000");
                expect(
                    await this.subject.UNIV3_ORACLE_INTERFACE_ID()
                ).to.not.eq("0x00000000");
                expect(await this.subject.ORACLE_INTERFACE_ID()).to.not.eq(
                    "0x00000000"
                );
                expect(
                    await this.subject.MELLOW_ORACLE_INTERFACE_ID()
                ).to.not.eq("0x00000000");

                expect(
                    await this.subject.CHIEF_TRADER_INTERFACE_ID()
                ).to.not.eq("0x00000000");
                expect(await this.subject.TRADER_INTERFACE_ID()).to.not.eq(
                    "0x00000000"
                );
                expect(await this.subject.ZERO_INTERFACE_ID()).to.be.eq(
                    "0x00000000"
                );

                expect(await this.subject.VAULT_INTERFACE_ID()).to.not.eq(
                    "0x00000000"
                );
                expect(
                    await this.subject.VAULT_REGISTRY_INTERFACE_ID()
                ).to.not.eq("0x00000000");
                expect(
                    await this.subject.INTEGRATION_VAULT_INTERFACE_ID()
                ).to.not.eq("0x00000000");
                expect(await this.subject.UNIV3_VAULT_INTERFACE_ID()).to.not.eq(
                    "0x00000000"
                );
                expect(await this.subject.AAVE_VAULT_INTERFACE_ID()).to.not.eq(
                    "0x00000000"
                );
                expect(await this.subject.YEARN_VAULT_INTERFACE_ID()).to.not.eq(
                    "0x00000000"
                );
                expect(
                    await this.subject.ERC20_ROOT_VAULT_GOVERNANCE()
                ).to.not.eq("0x00000000");
                expect(
                    await this.subject.ERC20_ROOT_VAULT_INTERFACE_ID()
                ).to.not.eq("0x00000000");

                expect(
                    await this.subject.PROTOCOL_GOVERNANCE_INTERFACE_ID()
                ).to.not.eq("0x00000000");
                expect(await this.subject.VALIDATOR_INTERFACE_ID()).to.not.eq(
                    "0x00000000"
                );
            });
        });
    }
);
