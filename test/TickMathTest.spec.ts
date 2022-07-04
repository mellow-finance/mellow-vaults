import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    generateSingleParams,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { TickMathTest } from "./types";
import { uint256 } from "./library/property";
import { deployMathTickTest } from "./library/Deployments";
import { BigNumber, BigNumberish } from "ethers";

type CustomContext = {};

type DeployOptions = {};

contract<TickMathTest, DeployOptions, CustomContext>("TickMathTest", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                this.subject = await deployMathTickTest();

                return this.subject;
            }
        );
    });

    function ithBitNotZero(value: BigNumberish, i: number) {
        let valueB = BigNumber.from(value);
        return valueB.mask(i + 1).gte(BigNumber.from(2).pow(i));
      }
      
    function getSqrtRatioAtTick(tick: number) {
        let absTick = BigNumber.from(Math.abs(tick));
      
        let p128 = BigNumber.from(2).pow(128);
        let p32 = BigNumber.from(2).pow(32);
        let ratio = ithBitNotZero(absTick, 0) ? BigNumber.from("0xfffcb933bd6fad37aa2d162d1a594001") : BigNumber.from("0x100000000000000000000000000000000");
        if (ithBitNotZero(absTick, 1)) {
            ratio = ratio.mul("0xfff97272373d413259a46990580e213a").div(p128);
        }
        if (ithBitNotZero(absTick, 2)) {
            ratio = ratio.mul("0xfff2e50f5f656932ef12357cf3c7fdcc").div(p128);
        }
        if (ithBitNotZero(absTick, 3)) {
            ratio = ratio.mul("0xffe5caca7e10e4e61c3624eaa0941cd0").div(p128);
        }
        if (ithBitNotZero(absTick, 4)) {
            ratio = ratio.mul("0xffcb9843d60f6159c9db58835c926644").div(p128);
        }
        if (ithBitNotZero(absTick, 5)) {
            ratio = ratio.mul("0xff973b41fa98c081472e6896dfb254c0").div(p128);
        }
        if (ithBitNotZero(absTick, 6)) {
            ratio = ratio.mul("0xff2ea16466c96a3843ec78b326b52861").div(p128);
        }
        if (ithBitNotZero(absTick, 7)) {
            ratio = ratio.mul("0xfe5dee046a99a2a811c461f1969c3053").div(p128);
        }
        if (ithBitNotZero(absTick, 8)) {
            ratio = ratio.mul("0xfcbe86c7900a88aedcffc83b479aa3a4").div(p128);
        }
        if (ithBitNotZero(absTick, 9)) {
            ratio = ratio.mul("0xf987a7253ac413176f2b074cf7815e54").div(p128);
        }
        if (ithBitNotZero(absTick, 10)) {
            ratio = ratio.mul("0xf3392b0822b70005940c7a398e4b70f3").div(p128);
        }
        if (ithBitNotZero(absTick, 11)) {
            ratio = ratio.mul("0xe7159475a2c29b7443b29c7fa6e889d9").div(p128);
        }
        if (ithBitNotZero(absTick, 12)) {
            ratio = ratio.mul("0xd097f3bdfd2022b8845ad8f792aa5825").div(p128);
        }
        if (ithBitNotZero(absTick, 13)) {
            ratio = ratio.mul("0xa9f746462d870fdf8a65dc1f90e061e5").div(p128);
        }
        if (ithBitNotZero(absTick, 14)) {
            ratio = ratio.mul("0x70d869a156d2a1b890bb3df62baf32f7").div(p128);
        }
        if (ithBitNotZero(absTick, 15)) {
            ratio = ratio.mul("0x31be135f97d08fd981231505542fcfa6").div(p128);
        }
        if (ithBitNotZero(absTick, 16)) {
            ratio = ratio.mul("0x9aa508b5b7a84e1c677de54f3e99bc9").div(p128);
        }
        if (ithBitNotZero(absTick, 17)) {
            ratio = ratio.mul("0x5d6af8dedb81196699c329225ee604").div(p128);
        }
        if (ithBitNotZero(absTick, 18)) {
            ratio = ratio.mul("0x2216e584f5fa1ea926041bedfe98").div(p128);
        }
        if (ithBitNotZero(absTick, 19)) {
            ratio = ratio.mul("0x48a170391f7dc42444e8fa2").div(p128);
        }
      
        if (tick > 0) {
            ratio = BigNumber.from(2).pow(256).sub(1).div(ratio);
        }
        return ratio.div(p32).add(ratio.mod(p32).eq(0) ? 0 : 1);
      
    }
    

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

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#getSqrtRatioAtTick", () => {
        it("sample from different intervals", async () => {
            for (let it = 0;  it < 20; it += 1) {
                let tick = genBigNumberBetweenPowersOfTwo(it, it + 1);
                if (tick.gt(887220)) {
                    continue;
                }
                expect(await this.subject.getSqrtRatioAtTick(tick)).to.be.eq(getSqrtRatioAtTick(tick.toNumber()));
            }

            for (let it = 0; it < 20; it += 1) {
                let tick = genBigNumberBetweenPowersOfTwo(it, it + 1).mul(-1);
                if (tick.lt(-887220)) {
                    continue;
                }
                expect(await this.subject.getSqrtRatioAtTick(tick)).to.be.eq(getSqrtRatioAtTick(tick.toNumber()));
            }
        });
    });

});
