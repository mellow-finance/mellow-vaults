import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { BigNumber } from "@ethersproject/bignumber";
import { TickMathTest, TickMathTest__factory } from "../test/types";
import { deployMathTickTest } from "../test/library/Deployments";

task("swap-amount", "Calculates swap amount needed to shift price in the pool")
    .addParam("shift", "Price shift in ticks", undefined, types.int)
    .addParam("width", "Width of positions opened by LStrategy in ticks", undefined, types.int)
    .addParam("positiontick", "Tick representing lower bound of upper position", undefined, types.string)
    .addParam("pooltick", "Tick representing price in the pool. If not given, ", undefined, types.string, true)
    .addParam("liquidity", "Total pool liquidity", undefined, types.string)
    .addParam("verify", "Check if calculated amount is correct by simulalting swap in this state", false, types.boolean, true)
    .setAction(async ({ ticks, width, positionTickString, poolTickString, liquidity, verify }, hre) => {
        if (width % 10 != 0) {
            console.error("Width should be multiple of 10 (tickSpacing)");
        } else if (positionTickString % 10 != 0) {
            console.error("Position tick should be multiple of 10 (tickSpacing)");
        } else {
            let poolTick = poolTickString != undefined ? +poolTickString : undefined;
            let { deltaXPriceDown, deltaYPriceUp, tickPriceDown, tickPriceUp } = await countSwapAmount(hre, ticks, width, +positionTickString, poolTick, BigNumber.from(liquidity));
            if (verify) {
                
            }
        }
    });

    async function liquidityToY(
        currentTick: number,
        tickUpper: number,
        tickLower: number,
        liquidity: BigNumber,
        tickMath: TickMathTest
    ) {
        let sqrtPriceX96 = await tickMath.getSqrtRatioAtTick(currentTick);
        let tickLowerPriceX96 = await tickMath.getSqrtRatioAtTick(
            tickLower
        );
        return sqrtPriceX96
            .sub(tickLowerPriceX96)
            .mul(liquidity)
            .div(BigNumber.from(2).pow(96));
    }

    async function liquidityToX(
        currentTick: number,
        tickUpper: number,
        tickLower: number,
        liquidity: BigNumber,
        tickMath: TickMathTest
    ) {
        let sqrtPriceX96 = await tickMath.getSqrtRatioAtTick(currentTick);
        let tickUpperPriceX96 = await tickMath.getSqrtRatioAtTick(
            tickUpper
        );
        let smth = tickUpperPriceX96
            .sub(sqrtPriceX96)
            .mul(BigNumber.from(2).pow(96));
        return liquidity.mul(smth).div(tickUpperPriceX96.mul(sqrtPriceX96));
    }

    function splitByLiquidityRatio(targetTick: number, upperPositionTickLower:number, upperPositionTickUpper:number, liqudity:BigNumber) 
    {
        let upperPositionMidTick = (upperPositionTickLower + upperPositionTickUpper) / 2;
        let liquidityRatio = Math.abs(targetTick - upperPositionMidTick);
        liquidityRatio = liquidityRatio / ((upperPositionTickUpper - upperPositionTickLower) / 2);
        let denom = 100000;
        return { lowerLiquidity: liqudity.mul(Math.round(denom * liquidityRatio)).div(denom), upperLiquidity: liqudity.mul(Math.round(denom * (1 - liquidityRatio))).div(denom) }

    }

    async function tokenAmountsToShiftPosition(currentTick: number, newTick: number, tickLower: number, tickUpper: number, liqudity: BigNumber, tickMath: TickMathTest) {
        // new tick = in bounds(poisiton, new tick)
        newTick = Math.max(newTick, tickLower);
        newTick = Math.min(newTick, tickUpper);

        // delta x = fx(liquidity, new price, current price)
        let currentX = await liquidityToX(currentTick, tickUpper, tickLower, liqudity, tickMath);
        let newX = await liquidityToX(newTick, tickUpper, tickLower, liqudity, tickMath);
        let deltaX = newX.sub(currentX);

        // delta y = fy(liquidity, new price, current price)
        let currentY = await liquidityToY(currentTick, tickUpper, tickLower, liqudity, tickMath);
        let newY = await liquidityToY(newTick, tickUpper, tickLower, liqudity, tickMath);
        let deltaY = newY.sub(currentY);
        return {deltaX, deltaY};
    }

async function countSwapAmount(hre: HardhatRuntimeEnvironment, tickShift: number, positionWidth: number, upperPositionTickLower: number, poolTick: number | undefined, totalLiquidity: BigNumber) {
    const { ethers } = hre;
    const MathTickTest: TickMathTest__factory = await ethers.getContractFactory(
        "TickMathTest"
    );
    const tickMath: TickMathTest = await MathTickTest.deploy();
    await tickMath.deployed();
    let lowerPositionTickLower = upperPositionTickLower - positionWidth / 2;
    let lowerPositionTickUpper = lowerPositionTickLower + positionWidth;
    let upperPositionTickUpper = upperPositionTickLower + positionWidth;
    let splitTick;

    // print liquidity to token0 token1 
    if (poolTick == undefined) {
        console.log("if upper and lower position's liquidities are equal, there is");
        splitTick = Math.round((upperPositionTickLower + lowerPositionTickUpper) / 2);
    } else {
        console.log("if pool tick is " + poolTick + ", there is");
        splitTick = poolTick;
    }
    let {lowerLiquidity, upperLiquidity} = splitByLiquidityRatio(splitTick, upperPositionTickLower, upperPositionTickUpper, totalLiquidity);
    let lowerToX = await liquidityToX(splitTick, lowerPositionTickUpper, lowerPositionTickLower, lowerLiquidity, tickMath);
    let upperToX = await liquidityToX(splitTick, upperPositionTickUpper, upperPositionTickLower, upperLiquidity, tickMath);
    let lowerToY = await liquidityToY(splitTick, lowerPositionTickUpper, lowerPositionTickLower, lowerLiquidity, tickMath);
    let upperToY = await liquidityToY(splitTick, upperPositionTickUpper, upperPositionTickLower, upperLiquidity, tickMath);
    console.log(lowerToX.toString() + " of 0 and " + lowerToY.toString() + " of 1 in lower vault");
    console.log(upperToX.toString() + " of 0 and " + upperToY.toString() + " of 1 in upper vault");
    console.log(lowerToX.add(upperToX).toString() + " of 0 and " + lowerToY.add(upperToY).toString() + " of 1 total\n");
    
    // choose current tick from upperPositionTickLower to upperPositionTickLower + positionWidth / 2
    let minPriceDownDeltaX = BigNumber.from(2).pow(255);
    let minPriceDownDeltaY = BigNumber.from(2).pow(255);
    let minPriceUpDeltaX = BigNumber.from(2).pow(255);
    let minPriceUpDeltaY = BigNumber.from(2).pow(255);
    let minPriceDownDeltaXAllPositions, minPriceDownDeltaYAllPositions, minPriceUpDeltaXAllPositions, minPriceUpDeltaYAllPositions;
    let tickPriceDown, tickPriceUp;
    let tickLowerBound =  poolTick == undefined ? upperPositionTickLower : poolTick;
    let tickUpperBound =  poolTick == undefined ? lowerPositionTickUpper : poolTick;
    for (let currentTick = tickLowerBound; currentTick <= tickUpperBound; currentTick++) {
        let priceDownTick = currentTick - tickShift;
        let priceUpTick = currentTick + tickShift;
        
        // liquidity = part of total liquidity depending on new price
        let {lowerLiquidity, upperLiquidity} = splitByLiquidityRatio(currentTick, upperPositionTickLower, upperPositionTickUpper, totalLiquidity);
        let midLiquidity = BigNumber.from("143542847431368536505");

        // tokens needed to swap in each position if price goes down
        let { deltaX:priceDownDeltaXLower, deltaY:priceDownDeltaYLower } = await tokenAmountsToShiftPosition(currentTick, priceDownTick, lowerPositionTickLower, lowerPositionTickUpper, lowerLiquidity, tickMath);
        let { deltaX:priceDownDeltaXUpper, deltaY:priceDownDeltaYUpper } = await tokenAmountsToShiftPosition(currentTick, priceDownTick, upperPositionTickLower, upperPositionTickUpper, upperLiquidity, tickMath);
        let { deltaX:priceDownDeltaXMid, deltaY:priceDownDeltaYMid } = await tokenAmountsToShiftPosition(currentTick, priceDownTick, -100, 100, midLiquidity, tickMath);
        let priceDownDeltaX = priceDownDeltaXLower.add(priceDownDeltaXUpper);
        let priceDownDeltaY = priceDownDeltaYLower.add(priceDownDeltaYUpper);
        if (priceDownDeltaX.lt(minPriceDownDeltaX)) {
            minPriceDownDeltaX = priceDownDeltaX;
            minPriceDownDeltaY = priceDownDeltaY; 
            minPriceDownDeltaXAllPositions = priceDownDeltaX.add(priceDownDeltaXMid);
            minPriceDownDeltaYAllPositions = priceDownDeltaX.add(priceDownDeltaYMid);
            tickPriceDown = currentTick;
        }

        // tokens needed to swap in each position if price goes up
        let { deltaX:priceUpDeltaXLower, deltaY:priceUpDeltaYLower } = await tokenAmountsToShiftPosition(currentTick, priceUpTick, lowerPositionTickLower, lowerPositionTickUpper, lowerLiquidity, tickMath);
        let { deltaX:priceUpDeltaXUpper, deltaY:priceUpDeltaYUpper } = await tokenAmountsToShiftPosition(currentTick, priceUpTick, upperPositionTickLower, upperPositionTickUpper, upperLiquidity, tickMath);
        let { deltaX:priceUpDeltaXMid, deltaY:priceUpDeltaYMid } = await tokenAmountsToShiftPosition(currentTick, priceUpTick, -100, 100, midLiquidity, tickMath);
        let priceUpDeltaX = priceUpDeltaXLower.add(priceUpDeltaXUpper).add(priceUpDeltaXMid);
        let priceUpDeltaY = priceUpDeltaYLower.add(priceUpDeltaYUpper).add(priceUpDeltaYMid);
        if (priceUpDeltaY.lt(minPriceUpDeltaY)) {
            minPriceUpDeltaY = priceUpDeltaY;
            minPriceUpDeltaX = priceUpDeltaX; 
            minPriceUpDeltaXAllPositions = priceUpDeltaX.add(priceUpDeltaXMid);
            minPriceUpDeltaYAllPositions = priceUpDeltaX.add(priceUpDeltaYMid);
            tickPriceUp = currentTick;
        }        
    }
    console.log("To lower price for " + tickShift + " ticks, you need to swap at least");
    console.log(minPriceDownDeltaX.toString() + " of 0 for " + minPriceDownDeltaY.abs().toString() + " of 1");
    console.log("To higher price for " + tickShift + " ticks, you need to swap at least");
    console.log(minPriceUpDeltaY.toString() + " of 1 for " + minPriceUpDeltaX.abs().toString() + " of 0");

    return { deltaXPriceDown: minPriceDownDeltaXAllPositions, deltaYPriceUp: minPriceUpDeltaYAllPositions, tickPriceDown, tickPriceUp };
}
