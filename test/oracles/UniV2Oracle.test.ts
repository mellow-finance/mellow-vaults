import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { contract } from "../library/setup";
import { expect } from "chai";
import { UniV2Oracle } from "../types";

import {
    UNIV2_ORACLE_INTERFACE_ID,
    UNIV3_VAULT_INTERFACE_ID,
} from "../library/Constants";
import { ContractMetaBehaviour } from "../behaviors/contractMeta";

type CustomContext = {
    uniV2Oracle: UniV2Oracle;
};

type DeployOptions = {};

contract<UniV2Oracle, DeployOptions, CustomContext>(
    "UniV2Oracle",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    this.subject = await ethers.getContract("UniV2Oracle");
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#contructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
                expect(ethers.constants.AddressZero).to.not.eq(
                    await this.subject.factory()
                );
            });
        });

        describe("#price", () => {
            it("retruns prices for [uscd, weth] pair", async () => {
                const pricesResult = await this.subject.priceX96(
                    this.usdc.address,
                    this.weth.address,
                    BigNumber.from(1 << (await this.subject.safetyIndex()))
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(1);
                expect(safetyIndices.length).to.be.eq(1);
                expect(safetyIndices[0]).to.be.eq(BigNumber.from(1));
            });

            it("retruns prices for [weth, usdc] pair", async () => {
                const pricesResult = await this.subject.priceX96(
                    this.weth.address,
                    this.usdc.address,
                    BigNumber.from(1 << (await this.subject.safetyIndex()))
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(1);
                expect(safetyIndices.length).to.be.eq(1);
                expect(safetyIndices[0]).to.be.eq(BigNumber.from(1));
            });

            describe("edges cases:", () => {
                describe("when one of tokens is zero", () => {
                    it("does not return prices", async () => {
                        let pricesResult = await this.subject.priceX96(
                            ethers.constants.AddressZero,
                            ethers.constants.AddressZero,
                            BigNumber.from(
                                1 << (await this.subject.safetyIndex())
                            )
                        );

                        let pricesX96 = pricesResult.pricesX96;
                        expect(pricesX96).to.be.empty;
                    });
                });
                describe("when first of safetyIndicesSet is missing", () => {
                    it("does not return prices", async () => {
                        const badMask =
                            63 ^ (1 << (await this.subject.safetyIndex()));
                        let pricesResult = await this.subject.priceX96(
                            this.usdc.address,
                            this.weth.address,
                            badMask
                        );
                        let pricesX96 = pricesResult.pricesX96;
                        expect(pricesX96).to.be.empty;
                    });
                });
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true for IUniV2Oracle interface (${UNIV2_ORACLE_INTERFACE_ID})`, async () => {
                let isSupported = await this.subject.supportsInterface(
                    UNIV2_ORACLE_INTERFACE_ID
                );
                expect(isSupported).to.be.true;
            });

            describe("edge cases:", () => {
                describe("when contract does not support the given interface", () => {
                    it("returns false", async () => {
                        let isSupported =
                            await this.subject.supportsInterface(
                                UNIV3_VAULT_INTERFACE_ID
                            );
                        expect(isSupported).to.be.false;
                    });
                });
            });
        });

        ContractMetaBehaviour.call(this, { contractName:"UniV2Oracle", contractVersion:"1.0.0" });
    }
);
