import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { expect } from "chai";
import { ChainlinkOracle, IAggregatorV3, IERC20Metadata } from "../types";

import {
    ERC165_INTERFACE_ID,
    UNIV2_ORACLE_INTERFACE_ID,
    CHAINLINK_ORACLE_INTERFACE_ID,
} from "../library/Constants";
import Exceptions from "../library/Exceptions";
import Common from "../library/Common";

type CustomContext = {
    chainlinkOracle: ChainlinkOracle;
    chainlinkEth: string;
    chainlinkBtc: string;
    chainlinkUsdc: string;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "ChainlinkOracle",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    this.chainlinkOracle = await ethers.getContract(
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

        describe.only("#contructor", () => {
            it("creates ChainlinkOracle", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.chainlinkOracle.address
                );
            });

            it("initializes ChainlinkOracle name", async () => {
                expect("ChainlinkOracle").to.be.eq(
                    await this.chainlinkOracle.contractName()
                );
            });

            it("initializes ChainlinkOracle version", async () => {
                expect("1.0.0").to.be.eq(
                    await this.chainlinkOracle.contractVersion()
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

        describe.only("#price", () => {
            it("empty response if pools index is zero", async () => {
                const pricesResult = await this.chainlinkOracle.price(
                    this.usdc.address,
                    this.weth.address,
                    BigNumber.from(31)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(0);
                expect(safetyIndices.length).to.be.eq(0);
            });

            it("empty response for wrong tokens", async () => {
                const pricesResult = await this.chainlinkOracle.price(
                    ethers.constants.AddressZero,
                    this.usdc.address,
                    BigNumber.from(32)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(0);
                expect(safetyIndices.length).to.be.eq(0);
            });

            it("empty response if first call of queryChainlinkOracle failed", async () => {
                await this.chainlinkOracle
                    .connect(this.admin)
                    .addChainlinkOracles(
                        [this.weth.address, this.usdc.address],
                        [this.weth.address, this.chainlinkUsdc]
                    );
                const pricesResult = await this.chainlinkOracle.price(
                    this.weth.address,
                    this.usdc.address,
                    BigNumber.from(32)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(0);
                expect(safetyIndices.length).to.be.eq(0);
            });

            it("empty response if second call of queryChainlinkOracle failed", async () => {
                await this.chainlinkOracle
                    .connect(this.admin)
                    .addChainlinkOracles(
                        [this.weth.address, this.usdc.address],
                        [this.weth.address, this.chainlinkUsdc]
                    );
                const pricesResult = await this.chainlinkOracle.price(
                    this.usdc.address,
                    this.weth.address,
                    BigNumber.from(32)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(0);
                expect(safetyIndices.length).to.be.eq(0);
            });

            it("returns correct pricesX96 and safetyIndexes", async () => {
                await this.chainlinkOracle
                    .connect(this.admin)
                    .addChainlinkOracles(
                        [this.weth.address, this.usdc.address],
                        [this.chainlinkEth, this.chainlinkUsdc]
                    );
                const pricesResult = await this.chainlinkOracle.price(
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

        describe.only("#supportsInterface", () => {
            it(`returns true for ERC165 interface (${ERC165_INTERFACE_ID})`, async () => {
                let isSupported = await this.chainlinkOracle.supportsInterface(
                    ERC165_INTERFACE_ID
                );
                expect(isSupported).to.be.true;
            });

            it(`returns true for ChainlinkOracle interface (${CHAINLINK_ORACLE_INTERFACE_ID})`, async () => {
                let isSupported = await this.chainlinkOracle.supportsInterface(
                    CHAINLINK_ORACLE_INTERFACE_ID
                );
                expect(isSupported).to.be.true;
            });

            it("returns false when contract does not support the given interface", async () => {
                let isSupported = await this.chainlinkOracle.supportsInterface(
                    UNIV2_ORACLE_INTERFACE_ID
                );
                expect(isSupported).to.be.false;
            });
        });

        describe.only("#addChainlinkOracles", () => {
            it(`non-empty response of price function with set oracles by the addChainlinkOracles function`, async () => {
                await this.chainlinkOracle
                    .connect(this.admin)
                    .addChainlinkOracles(
                        [this.weth.address, this.usdc.address],
                        [this.chainlinkEth, this.chainlinkUsdc]
                    );
                const pricesResult = await this.chainlinkOracle.price(
                    this.weth.address,
                    this.usdc.address,
                    BigNumber.from(32)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(1);
                expect(safetyIndices.length).to.be.eq(1);
            });

            it(`reverts with ${Exceptions.INVALID_VALUE} b.o. different lengths of arrays`, async () => {
                await expect(
                    this.chainlinkOracle
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

            it(`reverts with ${Exceptions.FORBIDDEN} b.o. sender is not with admin rights`, async () => {
                await expect(
                    this.chainlinkOracle.addChainlinkOracles([], [])
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });

            it(`function emits OraclesAdded event`, async () => {
                await expect(
                    this.chainlinkOracle
                        .connect(this.admin)
                        .addChainlinkOracles(
                            [this.weth.address, this.usdc.address],
                            [this.chainlinkEth, this.chainlinkUsdc]
                        )
                ).to.emit(this.chainlinkOracle, "OraclesAdded");
            });
        });

        describe.only("#hasOracle", () => {
            it(`returns true if oracle is supported`, async () => {
                [
                    this.usdc.address,
                    this.weth.address,
                    this.wbtc.address,
                ].forEach(async (token) => {
                    var isSupported = await this.chainlinkOracle.hasOracle(
                        token
                    );
                    expect(isSupported).to.be.true;
                });
            });
            it(`returns false if oracle is not supported`, async () => {
                [this.chainlinkEth].forEach(async (token) => {
                    var isSupported = await this.chainlinkOracle.hasOracle(
                        token
                    );
                    expect(isSupported).to.be.false;
                });
            });
        });

        describe.only("#supportedTokens", () => {
            it(`returns list of supported tokens`, async () => {
                var tokens = await this.chainlinkOracle.supportedTokens();
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
    }
);
