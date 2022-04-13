import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { expect } from "chai";
import { DefaultAccessControlLateInit } from "../types";

type CustomContext = {
    defaultAccessControlLateInit: DefaultAccessControlLateInit;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "DefaultAccessControlLateInit",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { deployments, getNamedAccounts } = hre;
                    const { deploy } = deployments;
                    const { deployer } = await getNamedAccounts();

                    await deploy("DefaultAccessControlLateInit", {
                        from: deployer,
                        args: [],
                        log: true,
                        autoMine: true,
                    });

                    this.defaultAccessControlLateInit =
                        await ethers.getContract(
                            "DefaultAccessControlLateInit"
                        );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#isOperator", () => {
            it("returns `true` if sender is an operator, `false` otherwise", async () => {
                {
                    var isOperator =
                        await this.defaultAccessControlLateInit.isOperator(
                            this.admin.address
                        );
                    expect(isOperator).to.be.false;
                }
                {
                    await this.defaultAccessControlLateInit.init(
                        this.admin.address
                    );
                    var isOperator =
                        await this.defaultAccessControlLateInit.isOperator(
                            this.admin.address
                        );
                    expect(isOperator).to.be.true;
                }
            });
        });

        describe("#isAdmin", () => {
            it("returns `true` if sender is an admin, `false` otherwise", async () => {
                {
                    var isAdmin =
                        await this.defaultAccessControlLateInit.isAdmin(
                            this.admin.address
                        );
                    expect(isAdmin).to.be.false;
                }
                {
                    await this.defaultAccessControlLateInit.init(
                        this.admin.address
                    );
                    var isAdmin =
                        await this.defaultAccessControlLateInit.isAdmin(
                            this.admin.address
                        );
                    expect(isAdmin).to.be.true;
                }
            });
        });
    }
);
