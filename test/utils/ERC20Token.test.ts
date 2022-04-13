import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { expect } from "chai";
import { CommonTest, MockERC20Token } from "../types";
import Exceptions from "../library/Exceptions";
import { sleep, sleepTo } from "../library/Helpers";
import { BigNumber } from "ethers";

type CustomContext = {
    erc20Token: MockERC20Token;
    commonTest: CommonTest;
};

type DeployOptions = {};

import { Bytes, concat } from "@ethersproject/bytes";
import { keccak256 } from "@ethersproject/keccak256";
import { toUtf8Bytes } from "@ethersproject/strings";

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "ERC20Token",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { deployments, getNamedAccounts } = hre;
                    const { deploy } = deployments;
                    const { deployer } = await getNamedAccounts();

                    await deploy("MockERC20Token", {
                        from: deployer,
                        args: [],
                        log: true,
                        autoMine: true,
                    });

                    this.erc20Token = await ethers.getContract(
                        "MockERC20Token"
                    );

                    await deploy("CommonTest", {
                        from: deployer,
                        args: [],
                        log: true,
                        autoMine: true,
                    });

                    this.commonTest = await ethers.getContract("CommonTest");

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe.only("#constructor", () => {
            it("deployes a new contract", async () => {
                expect(ethers.constants.AddressZero).not.to.be.eq(
                    this.erc20Token.address
                );
            });
        });

        describe.only("#DOMAIN_SEPARATOR", () => {
            it("returns domaint separator", async () => {
                var separator = await this.erc20Token.DOMAIN_SEPARATOR();
                expect(ethers.constants.AddressZero).not.to.be.eq(separator);
            });
        });

        describe.only("#approve", () => {
            it("allows `sender` to transfer `spender` an `amount` and emits Approval", async () => {
                var [spender] = await ethers.getSigners();
                await expect(
                    this.erc20Token.approve(spender.address, BigNumber.from(10))
                ).to.emit(this.erc20Token, "Approval");
            });
        });

        describe.only("#transfer", () => {
            it("transfers `amount` from `msg.sender` to `to`", async () => {
                var [to] = await ethers.getSigners();
                var amount: BigNumber = BigNumber.from(10000);
                await this.erc20Token.mint(this.deployer.address, amount);
                await expect(
                    this.erc20Token.transfer(to.address, amount)
                ).to.emit(this.erc20Token, "Transfer");
            });
        });

        describe.only("#transferFrom", () => {
            it("transfers `amount` from `from` to `to` if allowed", async () => {
                var [from] = await ethers.getSigners();

                var income = BigNumber.from(10000);
                await this.erc20Token.mint(from.address, income);
                var outcome = BigNumber.from(5000);
                await this.erc20Token.burn(from.address, outcome);
                var amount = income.sub(outcome);
                var [to] = await ethers.getSigners();
                await this.erc20Token.connect(from).approve(to.address, amount);
                await expect(
                    this.erc20Token.transferFrom(
                        from.address,
                        to.address,
                        amount
                    )
                ).to.emit(this.erc20Token, "Transfer");
            });
        });

        describe.only("#permit", () => {
            xit("emits Approval", async () => {
                var owner = this.deployer.address;
                var spender = this.deployer.address;

                var value = BigNumber.from(0);
                var deadline = BigNumber.from(2).pow(100);
                var nonces = BigNumber.from(0);

                let message: Bytes | string = keccak256(
                    concat([
                        await this.erc20Token.PERMIT_TYPEHASH(),
                        owner,
                        spender,
                        value.toHexString(),
                        nonces.toHexString(),
                        deadline.toHexString(),
                    ])
                );
                message = message.substring(2);
                console.log("Message:", message);

                const signature = await this.deployer.signMessage(message);
                var [r, s, v] = await this.commonTest.splitSignature(signature);

                await expect(
                    this.erc20Token.permit(
                        owner,
                        spender,
                        value,
                        deadline,
                        v,
                        r,
                        s
                    )
                ).to.emit(this.erc20Token, "Approval");
            });

            describe("edge cases:", () => {
                describe("when deadline less than current timestamp", () => {
                    it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                        await sleep(1000);
                        var [owner] = await ethers.getSigners();
                        var [spender] = await ethers.getSigners();
                        const messageHash = ethers.utils
                            .hashMessage(this.deployer.address)
                            .substring(2);
                        const signature = await this.deployer.signMessage(
                            messageHash
                        );
                        var [r, s, v] = await this.commonTest.splitSignature(
                            signature
                        );

                        await expect(
                            this.erc20Token.permit(
                                owner.address,
                                spender.address,
                                0,
                                0,
                                v,
                                r,
                                s
                            )
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    });
                });
                describe("when incorrect signature", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        var [owner] = await ethers.getSigners();
                        var [spender] = await ethers.getSigners();
                        const messageHash = ethers.utils
                            .hashMessage(ethers.constants.AddressZero)
                            .substring(2);
                        const signature = await this.deployer.signMessage(
                            messageHash
                        );
                        var [r, s, v] = await this.commonTest.splitSignature(
                            signature
                        );
                        await expect(
                            this.erc20Token.permit(
                                owner.address,
                                spender.address,
                                0,
                                BigNumber.from(2).pow(100),
                                v,
                                r,
                                s
                            )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });
    }
);
