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
import { reduceWhile, T } from "ramda";
import { string } from "fast-check";
import { threadId } from "worker_threads";

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

        describe("#constructor", () => {
            it("deployes a new contract", async () => {
                expect(ethers.constants.AddressZero).not.to.be.eq(
                    this.erc20Token.address
                );
            });
        });

        describe("#DOMAIN_SEPARATOR", () => {
            it("returns domaint separator", async () => {
                var separator = await this.erc20Token.DOMAIN_SEPARATOR();
                expect(ethers.constants.AddressZero).not.to.be.eq(separator);
            });
        });

        describe("#approve", () => {
            it("allows `sender` to transfer `spender` an `amount` and emits Approval", async () => {
                var [spender] = await ethers.getSigners();
                await expect(
                    this.erc20Token.approve(spender.address, BigNumber.from(10))
                ).to.emit(this.erc20Token, "Approval");
            });
        });

        describe("#transfer", () => {
            it("transfers `amount` from `msg.sender` to `to`", async () => {
                var [to] = await ethers.getSigners();
                var amount: BigNumber = BigNumber.from(10000);
                await this.erc20Token.mint(this.deployer.address, amount);
                await expect(
                    this.erc20Token.transfer(to.address, amount)
                ).to.emit(this.erc20Token, "Transfer");
            });
        });

        describe("#transferFrom", () => {
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

        const bytesToHex = (arr: Bytes) => {
            var x =
                "0x" +
                Array.from(arr, (byte) =>
                    ("0" + (byte & 0xff).toString(16)).slice(-2)
                ).join("");
            return convertToHex(x);
        };

        describe.only("#permit", () => {
            xit("emits Approval", async () => {
                await this.erc20Token.initERC20("ERC20", "ERC20");
                var owner = await this.deployer.getAddress();
                var spender = await this.deployer.getAddress();

                var value = BigNumber.from(0);
                var deadline = BigNumber.from(2).pow(100);
                var nonces = BigNumber.from(0);
                var message: Bytes = concat([
                    convertToHex(await this.erc20Token.PERMIT_TYPEHASH()),
                    convertToHex(owner),
                    convertToHex(spender),
                    convertBigNumberToHex(value),
                    convertBigNumberToHex(nonces),
                    convertBigNumberToHex(deadline),
                ]);
                const domainSeparator =
                    await this.erc20Token.DOMAIN_SEPARATOR();
                function hashMessage(message: Bytes): string {
                    return keccak256(
                        concat(["0x1901", domainSeparator, keccak256(message)])
                    );
                }

                let messageHash = hashMessage(message).substring(2);

                console.log("TEST# MessageHash:", messageHash);

                const TOKEN_DIGEST =
                    "0xe8cfbb4ac172b0e03c797967bcdfd655f1f46bafb0f4683c056cd11d388e1762".substring(
                        2
                    );
                expect(TOKEN_DIGEST).to.be.eq(messageHash);

                const domain = {
                    name: await this.erc20Token.name(),
                    version: "1",
                    chainId: 31337,
                    verifyingContract: this.erc20Token.address,
                };

                // const types = {

                // };

                // const value = {

                // };

                //const signature = await this.deployer._signTypedData(domain, types, value);
                const signature = await this.deployer.signMessage(messageHash);

                const getMessageHash = () => {
                    return ethers.utils.keccak256(
                        Array.from(
                            `\x19Ethereum Signed Message:\n${messageHash.length.toString()}${messageHash}`, // works correctly
                            //`0x1901${domainSeparator}${messageHash}`, // works incorrectly
                            (x) => x.charCodeAt(0)
                        )
                    );
                };

                var hsh = getMessageHash();

                var recoveredSignature = await this.commonTest.recoverSigner(
                    hsh,
                    signature
                );
                console.log(
                    "Recovered and my owner:",
                    recoveredSignature,
                    owner
                );
                expect(recoveredSignature).to.be.eq(owner);

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
