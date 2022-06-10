import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { BigNumber } from "@ethersproject/bignumber";
import { TickMathTest, TickMathTest__factory } from "../test/types";
import { deployMathTickTest } from "../test/library/Deployments";

task("swap-amount", "Calculates swap amount needed to shift price in the pool")
    .addParam("ticks", "Price shift in ticks", undefined, types.int)
    .addParam("tvl", "Total pool liquidity in $", undefined, types.int)
    .setAction(async ({ ticks, tvl }, hre) => {
        await countSwapAmount(hre, ticks, tvl);
    });


    async function liquidityToY(
        sqrtPriceX96: BigNumber,
        tickUpper: number,
        tickLower: number,
        liquidity: BigNumber,
        tickMath: TickMathTest
    ) {
        let tickLowerPriceX96 = await tickMath.getSqrtRatioAtTick(
            tickLower
        );
        return sqrtPriceX96
            .sub(tickLowerPriceX96)
            .mul(liquidity)
            .div(BigNumber.from(2).pow(96));
    }

    async function liquidityToX(
        sqrtPriceX96: BigNumber,
        tickUpper: number,
        tickLower: number,
        liquidity: BigNumber,
        tickMath: TickMathTest
    ) {
        let tickUpperPriceX96 = await tickMath.getSqrtRatioAtTick(
            tickUpper
        );
        let smth = tickUpperPriceX96
            .sub(sqrtPriceX96)
            .mul(BigNumber.from(2).pow(96));
        return liquidity.mul(smth).div(tickUpperPriceX96.mul(sqrtPriceX96));
    }

    function sqrtPriceAfterYChange(
        sqrtPriceX96: BigNumber,
        deltaY: BigNumber,
        liquidity: BigNumber
    ) {
        return sqrtPriceX96.sub(
            deltaY.mul(BigNumber.from(2).pow(96)).div(liquidity)
        );
    }

    function sqrtPriceAfterXChange(
        sqrtPriceX96: BigNumber,
        deltaX: BigNumber,
        liquidity: BigNumber
    ) {
        let smth = deltaX
            .mul(sqrtPriceX96)
            .div(BigNumber.from(2).pow(96))
            .mul(-1);
        return liquidity.mul(sqrtPriceX96).div(smth.add(liquidity));
    }

    function yAmountUsedInSwap(
        sqrtPriceBeforeSwapX96: BigNumber,
        sqrtPriceAfterSwapX96: BigNumber,
        liquidity: BigNumber
    ) {
        return liquidity
            .mul(sqrtPriceAfterSwapX96.sub(sqrtPriceBeforeSwapX96))
            .div(BigNumber.from(2).pow(96))
            .abs();
    }

    function xAmountUsedInSwap(
        sqrtPriceBeforeSwapX96: BigNumber,
        sqrtPriceAfterSwapX96: BigNumber,
        liquidity: BigNumber
    ) {
        return liquidity
            .mul(sqrtPriceAfterSwapX96.sub(sqrtPriceBeforeSwapX96))
            .div(
                sqrtPriceAfterSwapX96
                    .mul(sqrtPriceBeforeSwapX96)
                    .div(BigNumber.from(2).pow(96))
            )
            .abs();
    }

async function countSwapAmount(hre: HardhatRuntimeEnvironment, ticks: number, liqudity: number) {
    
}
