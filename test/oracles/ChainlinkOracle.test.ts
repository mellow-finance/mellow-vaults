import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { contract } from "../library/setup";
import { expect } from "chai";
import { ChainlinkOracle, IAggregatorV3, IERC20Metadata } from "../types";

import {
    UNIV2_ORACLE_INTERFACE_ID,
    CHAINLINK_ORACLE_INTERFACE_ID,
} from "../library/Constants";
import Exceptions from "../library/Exceptions";
import Common from "../library/Common";
import { ContractMetaBehaviour } from "../behaviors/contractMeta";

type CustomContext = {
    chainlinkOracle: ChainlinkOracle;
    chainlinkEth: string;
    chainlinkBtc: string;
    chainlinkUsdc: string;
};

type DeployOptions = {};

contract<ChainlinkOracle, DeployOptions, CustomContext>(
    "ChainlinkOracle",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    this.subject = await ethers.getContract(
                        "ChainlinkOracle"
                    );
                    const { chainlinkEth, chainlinkBtc, chainlinkUsdc } =
                        await hre.getNamedAccounts();
                    this.chainlinkEth = chainlinkEth;
                    this.chainlinkBtc = chainlinkBtc;
                    this.chainlinkUsdc = chainlinkUsdc;
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
            });
        });

        const getPriceAndDecimals = async (token: string, oracle: string) => {
            var chainlinkOracle0: IAggregatorV3 = await ethers.getContractAt(
                "IAggregatorV3",
                oracle
            );
            var [, price0] = await chainlinkOracle0.latestRoundData();
            var metaData: IERC20Metadata = await ethers.getContractAt(
                "IERC20Metadata",
                token
            );
            var metaDataDecimals = await metaData.decimals();
            var aggregatorDecimals = await chainlinkOracle0.decimals();
            var decimals0 = -metaDataDecimals - aggregatorDecimals;
            return [price0, BigNumber.from(decimals0)];
        };

        describe("#price", () => {
            describe("when pools index is zero", () => {
                it("does not return prices", async () => {
                    const pricesResult = await this.subject.price(
                        this.usdc.address,
                        this.weth.address,
                        BigNumber.from(31)
                    );

                    const pricesX96 = pricesResult.pricesX96;
                    const safetyIndices = pricesResult.safetyIndices;
                    expect(pricesX96.length).to.be.eq(0);
                    expect(safetyIndices.length).to.be.eq(0);
                });
            });

            describe("when one of tokens is zero", () => {
                it("does not return prices", async () => {
                    const pricesResult = await this.subject.price(
                        ethers.constants.AddressZero,
                        this.usdc.address,
                        BigNumber.from(32)
                    );

                    const pricesX96 = pricesResult.pricesX96;
                    const safetyIndices = pricesResult.safetyIndices;
                    expect(pricesX96.length).to.be.eq(0);
                    expect(safetyIndices.length).to.be.eq(0);
                });
            });

            describe("when the first call of queryChainlinkOracle failed", () => {
                it("does not return prices", async () => {
                    await this.subject
                        .connect(this.admin)
                        .addChainlinkOracles(
                            [this.weth.address, this.usdc.address],
                            [this.weth.address, this.chainlinkUsdc]
                        );
                    const pricesResult = await this.subject.price(
                        this.weth.address,
                        this.usdc.address,
                        BigNumber.from(32)
                    );

                    const pricesX96 = pricesResult.pricesX96;
                    const safetyIndices = pricesResult.safetyIndices;
                    expect(pricesX96.length).to.be.eq(0);
                    expect(safetyIndices.length).to.be.eq(0);
                });
            });

            describe("when the second call of queryChainlinkOracle failed", () => {
                it("does not return prices", async () => {
                    await this.subject
                        .connect(this.admin)
                        .addChainlinkOracles(
                            [this.weth.address, this.usdc.address],
                            [this.weth.address, this.chainlinkUsdc]
                        );
                    const pricesResult = await this.subject.price(
                        this.usdc.address,
                        this.weth.address,
                        BigNumber.from(32)
                    );

                    const pricesX96 = pricesResult.pricesX96;
                    const safetyIndices = pricesResult.safetyIndices;
                    expect(pricesX96.length).to.be.eq(0);
                    expect(safetyIndices.length).to.be.eq(0);
                });
            });

            it("returns prices", async () => {
                await this.subject
                    .connect(this.admin)
                    .addChainlinkOracles(
                        [this.weth.address, this.usdc.address],
                        [this.chainlinkEth, this.chainlinkUsdc]
                    );
                const pricesResult = await this.subject.price(
                    this.weth.address,
                    this.usdc.address,
                    BigNumber.from(32)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(1);
                expect(safetyIndices.length).to.be.eq(1);
                expect(safetyIndices[0]).to.be.eq(BigNumber.from(5));

                var [price0, decimals0] = await getPriceAndDecimals(
                    this.weth.address,
                    this.chainlinkEth
                );
                var [price1, decimals1] = await getPriceAndDecimals(
                    this.usdc.address,
                    this.chainlinkUsdc
                );

                if (decimals1.gte(decimals0)) {
                    price1 = price1.mul(
                        BigNumber.from(10).pow(decimals1.sub(decimals0))
                    );
                } else {
                    price0 = price0.mul(
                        BigNumber.from(10).pow(decimals0.sub(decimals1))
                    );
                }

                var correctPrice = price0.mul(Common.Q96).div(price1);

                expect(correctPrice).to.be.eq(pricesX96[0]);
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true for ChainlinkOracle interface (${CHAINLINK_ORACLE_INTERFACE_ID})`, async () => {
                let isSupported = await this.subject.supportsInterface(
                    CHAINLINK_ORACLE_INTERFACE_ID
                );
                expect(isSupported).to.be.true;
            });
            describe("edge cases:", () => {
                describe("when contract does not support the given interface", () => {
                    it("returns false", async () => {
                        let isSupported =
                            await this.subject.supportsInterface(
                                UNIV2_ORACLE_INTERFACE_ID
                            );
                        expect(isSupported).to.be.false;
                    });
                });
            });
        });

        describe("#addChainlinkOracles", () => {
            describe("when oracles have set by addChainLinkOracles function", () => {
                it("returns prices", async () => {
                    await this.subject
                        .connect(this.admin)
                        .addChainlinkOracles(
                            [this.weth.address, this.usdc.address],
                            [this.chainlinkEth, this.chainlinkUsdc]
                        );
                    const pricesResult = await this.subject.price(
                        this.weth.address,
                        this.usdc.address,
                        BigNumber.from(32)
                    );

                    const pricesX96 = pricesResult.pricesX96;
                    const safetyIndices = pricesResult.safetyIndices;
                    expect(pricesX96.length).to.be.eq(1);
                    expect(safetyIndices.length).to.be.eq(1);
                });
            });

            it("emits OraclesAdded event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .addChainlinkOracles(
                            [this.weth.address, this.usdc.address],
                            [this.chainlinkEth, this.chainlinkUsdc]
                        )
                ).to.emit(this.subject, "OraclesAdded");
            });

            describe("edge cases:", () => {
                describe("when arrays have different lengths", () => {
                    it(`reverts with ${Exceptions.INVALID_VALUE}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .addChainlinkOracles(
                                    [
                                        this.weth.address,
                                        this.usdc.address,
                                        this.wbtc.address,
                                    ],
                                    [this.chainlinkEth, this.chainlinkUsdc]
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                    });
                });

                describe("when sender has no admin righs", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await expect(
                            this.subject.addChainlinkOracles([], [])
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#hasOracle", () => {
            it("returns true if oracle is supported", async () => {
                [
                    this.usdc.address,
                    this.weth.address,
                    this.wbtc.address,
                ].forEach(async (token) => {
                    var isSupported = await this.subject.hasOracle(
                        token
                    );
                    expect(isSupported).to.be.true;
                });
            });

            describe("edge cases:", () => {
                describe("when oracle is not supported", () => {
                    it("returns false", async () => {
                        [this.chainlinkEth].forEach(async (token) => {
                            var isSupported =
                                await this.subject.hasOracle(token);
                            expect(isSupported).to.be.false;
                        });
                    });
                });
            });
        });

        describe("#supportedTokens", () => {
            it("returns list of supported tokens", async () => {
                var tokens = await this.subject.supportedTokens();
                expect(tokens.length).to.be.eq(3);
                [
                    this.usdc.address,
                    this.weth.address,
                    this.wbtc.address,
                ].forEach((token) => {
                    expect(tokens.includes(token)).to.be.true;
                });
            });
        });
        
        ContractMetaBehaviour.call(this, { contractName:"ChainlinkOracle", contractVersion:"1.0.0" });
    }
);
