import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { contract } from "../library/setup";
import { expect } from "chai";
import { CommonTest, MockERC20Token } from "../types";
import Exceptions from "../library/Exceptions";
import { sleep } from "../library/Helpers";
import { BigNumber } from "ethers";

type CustomContext = {
    commonTest: CommonTest;
};

type DeployOptions = {};

import { Bytes, concat } from "@ethersproject/bytes";
import { keccak256 } from "@ethersproject/keccak256";

contract<MockERC20Token, DeployOptions, CustomContext>(
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

                    this.subject = await ethers.getContract("MockERC20Token");

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

        describe("#constructor", () => {
            it("deployes a new contract", async () => {
                expect(ethers.constants.AddressZero).not.to.be.eq(
                    this.subject.address
                );
            });
        });

        describe("#DOMAIN_SEPARATOR", () => {
            it("returns domaint separator", async () => {
                var separator = await this.subject.DOMAIN_SEPARATOR();
                expect(ethers.constants.AddressZero).not.to.be.eq(separator);
            });
        });

        describe("#approve", () => {
            it("allows `sender` to transfer `spender` an `amount` and emits Approval", async () => {
                var [spender] = await ethers.getSigners();
                await expect(
                    this.subject.approve(spender.address, BigNumber.from(10))
                ).to.emit(this.subject, "Approval");
            });
        });

        describe("#transfer", () => {
            it("transfers `amount` from `msg.sender` to `to`", async () => {
                var [to] = await ethers.getSigners();
                var amount: BigNumber = BigNumber.from(10000);
                await this.subject.mint(this.deployer.address, amount);
                await expect(this.subject.transfer(to.address, amount)).to.emit(
                    this.subject,
                    "Transfer"
                );
            });
        });

        describe("#transferFrom", () => {
            it("transfers `amount` from `from` to `to` if allowed", async () => {
                var [from] = await ethers.getSigners();

                var income = BigNumber.from(10000);
                await this.subject.mint(from.address, income);
                var outcome = BigNumber.from(5000);
                await this.subject.burn(from.address, outcome);
                var amount = income.sub(outcome);
                var [to] = await ethers.getSigners();
                await this.subject.connect(from).approve(to.address, amount);
                await expect(
                    this.subject.transferFrom(from.address, to.address, amount)
                ).to.emit(this.subject, "Transfer");
            });
        });

        const convertToHex = (str: string) => {
            str = str.substring(2);
            while (str.length < 64) {
                str = "0" + str;
            }
            str = "0x" + str;
            return str;
        };

        const convertBigNumberToHex = (val: BigNumber) => {
            var str = val.toHexString();
            return convertToHex(str);
        };

        describe("#permit", () => {
            it("emits Approval", async () => {
                await this.subject.initERC20("ERC20", "ERC20");
                var owner = await this.deployer.getAddress();
                var spender = await this.deployer.getAddress();

                var value = BigNumber.from(0);
                var deadline = BigNumber.from(2).pow(100);
                var nonces = BigNumber.from(0);
                var message: Bytes = concat([
                    convertToHex(await this.subject.PERMIT_TYPEHASH()),
                    convertToHex(owner),
                    convertToHex(spender),
                    convertBigNumberToHex(value),
                    convertBigNumberToHex(nonces),
                    convertBigNumberToHex(deadline),
                ]);
                const domainSeparator = await this.subject.DOMAIN_SEPARATOR();
                function hashMessage(message: Bytes): string {
                    return keccak256(
                        concat(["0x1901", domainSeparator, keccak256(message)])
                    );
                }

                const getSignatureByTypedData = async () => {
                    const domain = {
                        name: await this.subject.name(),
                        version: "1",
                        chainId: 31337,
                        verifyingContract: this.subject.address,
                    };

                    const types = {
                        Permit: [
                            { name: "owner", type: "address" },
                            { name: "spender", type: "address" },
                            { name: "value", type: "uint256" },
                            { name: "nonce", type: "uint256" },
                            { name: "deadline", type: "uint256" },
                        ],
                    };

                    const val = {
                        owner: owner,
                        spender: spender,
                        value: value,
                        nonce: nonces,
                        deadline: deadline,
                    };

                    return await this.deployer._signTypedData(
                        domain,
                        types,
                        val
                    );
                };

                const signature = await getSignatureByTypedData();
                var [r, s, v] = await this.commonTest.splitSignature(signature);
                await expect(
                    this.subject.permit(
                        owner,
                        spender,
                        value,
                        deadline,
                        v,
                        r,
                        s
                    )
                ).to.emit(this.subject, "Approval");
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
                            this.subject.permit(
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
                            this.subject.permit(
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
