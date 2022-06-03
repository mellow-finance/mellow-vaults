import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { contract } from "../library/setup";
import { expect } from "chai";
import Common from "../library/Common";

import { UniV3Oracle, IUniswapV3Pool, IUniswapV3Factory } from "../types";

import {
    UNIV2_ORACLE_INTERFACE_ID,
    UNIV3_ORACLE_INTERFACE_ID,
} from "../library/Constants";
import { ADDRESS_ZERO, TickMath } from "@uniswap/v3-sdk";
import { ContractMetaBehaviour } from "../behaviors/contractMeta";

type CustomContext = {
    uniV3Oracle: UniV3Oracle;
    uniswapV3Factory: IUniswapV3Factory;
};

type DeployOptions = {};

contract<UniV3Oracle, DeployOptions, CustomContext>("UniV3Oracle", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                this.subject = await ethers.getContract("UniV3Oracle");

                const { uniswapV3Factory } = await hre.getNamedAccounts();
                this.uniswapV3Factory = await hre.ethers.getContractAt(
                    "IUniswapV3Factory",
                    uniswapV3Factory
                );
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
        it("returns prices", async () => {
            for (var setBitsCount = 0; setBitsCount < 5; setBitsCount++) {
                const mask = BigNumber.from((1 << (setBitsCount + 1)) - 2);
                const pricesResult = await this.subject.price(
                    this.usdc.address,
                    this.weth.address,
                    mask
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;

                expect(pricesX96.length).to.be.eq(setBitsCount);
                expect(safetyIndices.length).to.be.eq(setBitsCount);
                for (var i = 0; i < safetyIndices.length; i++) {
                    expect(safetyIndices[i]).to.be.eq(BigNumber.from(i + 1));
                }
            }
        });

        it("correctly calculates prices for swapped tokens", async () => {
            for (var setBitsCount = 0; setBitsCount < 5; setBitsCount++) {
                const mask = BigNumber.from((1 << (setBitsCount + 1)) - 2);
                const DENOMINATOR_POWER = 96;
                const EPS_POWER = 32;

                const pricesResult = await this.subject.price(
                    this.usdc.address,
                    this.weth.address,
                    mask
                );

                const pricesResultSwapped = await this.subject.price(
                    this.weth.address,
                    this.usdc.address,
                    mask
                );

                const pricesX96 = pricesResult.pricesX96;
                const swappedPricesX96 = pricesResultSwapped.pricesX96;

                for (var i = 0; i < pricesX96.length; i++) {
                    // checks that prices[i] * swapped_prices[i] is (2^96)^2 with relative precision at least 2^(-32)
                    const multiplication = pricesX96[i].mul(
                        swappedPricesX96[i]
                    );
                    const expected_multiplication = BigNumber.from(2).pow(
                        DENOMINATOR_POWER * 2
                    );

                    const delta = multiplication
                        .sub(expected_multiplication)
                        .abs();
                    expect(
                        delta.mul(BigNumber.from(2).pow(EPS_POWER))
                    ).to.be.lt(multiplication);
                }

                expect(pricesX96.length).to.be.eq(setBitsCount);
            }
        });

        describe("edge cases:", () => {
            describe("when index of one of pools is zero", () => {
                it("does not return prices", async () => {
                    const pricesResult = await this.subject.price(
                        this.usdc.address,
                        ADDRESS_ZERO,
                        BigNumber.from(30)
                    );

                    const pricesX96 = pricesResult.pricesX96;
                    const safetyIndices = pricesResult.safetyIndices;
                    expect(pricesX96.length).to.be.eq(0);
                    expect(safetyIndices.length).to.be.eq(0);
                });
            });
        });
    });

    describe("#supportsInterface", () => {
        it(`returns true for IUniV3Oracle interface (${UNIV3_ORACLE_INTERFACE_ID})`, async () => {
            let isSupported = await this.subject.supportsInterface(
                UNIV3_ORACLE_INTERFACE_ID
            );
            expect(isSupported).to.be.true;
        });

        describe("when contract does not support the given interface", () => {
            it("returns false", async () => {
                let isSupported = await this.subject.supportsInterface(
                    UNIV2_ORACLE_INTERFACE_ID
                );
                expect(isSupported).to.be.false;
            });
        });
    });

    const calculateCorrectValuesForMask = async (
        poolUsdcWeth: IUniswapV3Pool,
        safetyIndexes: number
    ) => {
        const [spotSqrtPriceX96, , , observationCardinality] =
            await poolUsdcWeth.slot0();
        var correctPricesX96: BigNumber[] = [];
        var correctSafetyIndexes: BigNumber[] = [];

        const timeDeltas: number[] = [
            await this.subject.LOW_OBS_DELTA(),
            await this.subject.MID_OBS_DELTA(),
            await this.subject.HIGH_OBS_DELTA(),
        ];

        if (((safetyIndexes >> 1) & 1) > 0) {
            correctPricesX96.push(spotSqrtPriceX96);
            correctSafetyIndexes.push(BigNumber.from(1));
        }

        for (var i = 2; i < 5; i++) {
            if (((safetyIndexes >> i) & 1) == 0) {
                continue;
            }

            const timeDelta = timeDeltas[i - 2];
            const { tickCumulatives } = await poolUsdcWeth.observe([
                timeDelta,
                BigNumber.from(0),
            ]);
            const tickAverage = tickCumulatives[1]
                .sub(tickCumulatives[0])
                .div(timeDelta);

            correctPricesX96.push(
                BigNumber.from(
                    TickMath.getSqrtRatioAtTick(
                        tickAverage.toNumber()
                    ).toString()
                )
            );
            correctSafetyIndexes.push(BigNumber.from(i));
        }

        correctPricesX96 = correctPricesX96.map((price) => {
            return price.mul(price).div(Common.Q96);
        });

        return [correctPricesX96, correctSafetyIndexes];
    };

    const testForFeeAndMask = async (
        fee: number,
        token0: string,
        token1: string,
        safetyIndicesSet: number,
        correctResultSize: number
    ) => {
        if (token0 > token1) {
            [token0, token1] = [token1, token0];
        }

        const poolWethUsdcAddress = await this.uniswapV3Factory.getPool(
            token0,
            token1,
            fee
        );

        await this.subject
            .connect(this.admin)
            .addUniV3Pools([poolWethUsdcAddress]);
        const poolUsdcWeth: IUniswapV3Pool = await ethers.getContractAt(
            "IUniswapV3Pool",
            poolWethUsdcAddress
        );

        expect(await poolUsdcWeth.fee()).to.be.eq(fee);
        expect(await poolUsdcWeth.token0()).to.be.eq(token0);
        expect(await poolUsdcWeth.token1()).to.be.eq(token1);

        var [correctPricesX96, correctSafetyIndexes] =
            await calculateCorrectValuesForMask(poolUsdcWeth, safetyIndicesSet);

        const pricesResult = await this.subject.price(
            token0,
            token1,
            safetyIndicesSet
        );

        const pricesX96 = pricesResult.pricesX96;
        const safetyIndexes = pricesResult.safetyIndices;
        expect(pricesX96.length).to.be.eq(correctResultSize);
        expect(safetyIndexes.length).to.be.eq(correctResultSize);
        for (var i = 0; i < correctResultSize; i++) {
            expect(correctPricesX96[i]).to.be.eq(pricesX96[i]);
            expect(correctSafetyIndexes[i]).to.be.eq(safetyIndexes[i]);
        }
    };

    describe("#addUniV3Pools", () => {
        describe("when adding [weth, usdc] pools with fee = 500", () => {
            it("adds pools", async () => {
                await testForFeeAndMask(
                    500,
                    this.weth.address,
                    this.usdc.address,
                    30,
                    4
                );
            });
        });

        describe("when adding [weth, usdc] pools with fee = 3000", () => {
            it("adds pools", async () => {
                await testForFeeAndMask(
                    3000,
                    this.weth.address,
                    this.usdc.address,
                    30,
                    4
                );
            });
        });

        describe("when adding [weth, usdc] pools with fee = 10000", () => {
            it("does not return prices", async () => {
                await testForFeeAndMask(
                    10000,
                    this.weth.address,
                    this.usdc.address,
                    16,
                    1
                );
            });
        });
    });

    ContractMetaBehaviour.call(this, {
        contractName: "UniV3Oracle",
        contractVersion: "1.0.0",
    });
});
