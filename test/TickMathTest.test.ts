import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { generateSingleParams } from "./library/Helpers";
import { contract } from "./library/setup";
import { TickMathTest } from "./types";
import { uint256 } from "./library/property";
import { deployMathTickTest } from "./library/Deployments";
import { BigNumber, BigNumberish } from "ethers";

type CustomContext = {};

type DeployOptions = {};

contract<TickMathTest, DeployOptions, CustomContext>(
    "TickMathTest",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    this.subject = await deployMathTickTest();

                    return this.subject;
                }
            );
        });

        function genBigNumberBetweenPowersOfTwo(a: number, b: number) {
            let x = generateSingleParams(uint256);
            let upperBound = BigNumber.from(2).pow(b);
            let lowerBound = BigNumber.from(2).pow(a);
            if (x >= upperBound) {
                x = x.mod(upperBound);
            }
            if (x < lowerBound) {
                x = x.add(lowerBound);
            }
            return x;
        }
        
        const getRatioAtTick = (tick: number) => {
            const D = BigNumber.from(2).pow(1024);
            const Q96 = BigNumber.from(2).pow(96);
            let flag = tick < 0;
            if (flag) {
                tick = -tick;
            }

            var result = D.mul(Q96);
            var pow = BigNumber.from(10001);
            var dpow = BigNumber.from(10000);
            if (tick > 10) {
                const K = Math.max(10, Math.floor(Math.sqrt(tick)));
                var powK = pow.pow(K);
                var dpowK = dpow.pow(K);
                while (tick >= K) {
                    result = result.mul(powK).div(dpowK);
                    tick -= K;
                }
            }

            while (tick--) {
                result = result.mul(pow).div(dpow);
            }

            result = result.div(D);
            if (flag) {
                result = Q96.mul(Q96).div(result);
            }
            return result;
        };
        
        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#getSqrtRatioAtTick", () => {
            it("sample from positive intervals", async () => {
                for (let it = 0; it < 20; it += 1) {
                    let tick = genBigNumberBetweenPowersOfTwo(it, it + 1);
                    if (tick.gt(887220)) {
                        continue;
                    }
                    let realSqrtRatio = await this.subject.getSqrtRatioAtTick(tick);
                    let realRatio = realSqrtRatio.pow(2).div(BigNumber.from(2).pow(96));
                    let realRatioLower = realRatio.mul(99).div(100);
                    let realRatioUpper = realRatio.mul(101).div(100);
                    let expectedRatio = getRatioAtTick(tick.toNumber());

                    expect(realRatioLower.lte(expectedRatio)).to.be.true;
                    expect(realRatioUpper.gte(expectedRatio)).to.be.true;
                }
            });
            it("sample from negative intervals", async () => {
                for (let it = 0; it < 20; it += 1) {
                    let tick = genBigNumberBetweenPowersOfTwo(it, it + 1).mul(
                        -1
                    );
                    if (tick.lt(-887220)) {
                        continue;
                    }
                    let realSqrtRatio = await this.subject.getSqrtRatioAtTick(tick);
                    let realRatio = realSqrtRatio.pow(2).div(BigNumber.from(2).pow(96));
                    let realRatioLower = realRatio.mul(99).div(100);
                    let realRatioUpper = realRatio.mul(101).div(100);
                    let expectedRatio = getRatioAtTick(tick.toNumber());

                    expect(realRatioLower.lte(expectedRatio)).to.be.true;
                    expect(realRatioUpper.gte(expectedRatio)).to.be.true;
                }
            });
        });
    }
);
