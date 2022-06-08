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

async function countSwapAmount(hre: HardhatRuntimeEnvironment, ticks: number, tvl: number) {

    const { getNamedAccounts, ethers } = hre;
    const { deployer, uniswapV3Factory:uniswapV3FactoryAddress, wsteth, weth } = await getNamedAccounts();
    
    let uniswapV3Factory = await ethers.getContractAt(
        "IUniswapV3Factory",
        uniswapV3FactoryAddress
    );

    const MathTickTest: TickMathTest__factory = await ethers.getContractFactory(
        "TickMathTest"
    );
    const tickMath: TickMathTest = await MathTickTest.deploy();
    await tickMath.deployed();
    
    let uniV3PoolFee = 500;

    let uniV3PoolAddress = await uniswapV3Factory.getPool(
        wsteth,
        weth,
        uniV3PoolFee
    );
    console.log(uniV3PoolAddress);

    let uniV3Pool = await ethers.getContractAt(
        "IUniswapV3Pool",
        uniV3PoolAddress
    );
    let currentTick = (await uniV3Pool.slot0()).tick;
    console.log("tick is " + currentTick);

    let tickSpacing = await uniV3Pool.tickSpacing();
    
    let currentLiquidity = await uniV3Pool.liquidity();
    console.log("STARTED AT " + currentLiquidity.toString());
    for (let tick = currentTick; tick < currentTick + 100; tick++) {
        if (tick % tickSpacing == 0) {
            let tickInfo = await uniV3Pool.ticks(tick);
            console.log("liqNet at tick " + tick + ": " + tickInfo.liquidityNet.toString());
            currentLiquidity = currentLiquidity.add(
                tickInfo.liquidityNet
            );
            console.log(currentLiquidity.toString());
        }
    }
    console.log("TURN AROUND");

    currentLiquidity = await uniV3Pool.liquidity();
    for (let tick = currentTick; tick > currentTick - 300; tick--) {
        if (tick % tickSpacing == 0) {
            let tickInfo = await uniV3Pool.ticks(tick);
            console.log("liqNet at tick " + tick + ": " + tickInfo.liquidityNet.toString());
            currentLiquidity = currentLiquidity.sub(
                tickInfo.liquidityNet
            );
            console.log(currentLiquidity.toString());
        }
    }

    
    let zeroForOne = true;

    // let currentTick = (await uniV3Pool.slot0()).tick;
    // let currentPrice = (await uniV3Pool.slot0()).sqrtPriceX96;
    // let currentLiquidity = await uniV3Pool.liquidity();
    // let totalSwapAmount = BigNumber.from(0);
    // for (let tickIndex = 0; tickIndex < ticks; tickIndex++) {
    //     console.log("currentTick is " + currentTick.toString());
    //     let currentSwapAmount;
    //     if (zeroForOne) {
    //         currentSwapAmount = await liquidityToX(
    //             currentPrice,
    //             currentTick + 1,
    //             currentTick,
    //             currentLiquidity,
    //             tickMath
    //         );
    //     } else {
    //         currentSwapAmount = await liquidityToY(
    //             currentPrice,
    //             currentTick + 1,
    //             currentTick,
    //             currentLiquidity,
    //             tickMath
    //         );
    //     }
    //     let currentSwapAmountInOtherCoin: BigNumber,
    //         newPrice: BigNumber;
    //     if (zeroForOne) {
    //         newPrice = sqrtPriceAfterXChange(
    //             currentPrice,
    //             currentSwapAmount,
    //             currentLiquidity
    //         );
    //         currentSwapAmountInOtherCoin = yAmountUsedInSwap(
    //             currentPrice,
    //             newPrice,
    //             currentLiquidity
    //         );
    //     } else {
    //         newPrice = sqrtPriceAfterYChange(
    //             currentPrice,
    //             currentSwapAmount,
    //             currentLiquidity
    //         );
    //         currentSwapAmountInOtherCoin = xAmountUsedInSwap(
    //             currentPrice,
    //             newPrice,
    //             currentLiquidity
    //         );
    //     }
    //     totalSwapAmount = totalSwapAmount.add(currentSwapAmount);
    //     if (zeroForOne) {
    //         currentPrice = await tickMath.getSqrtRatioAtTick(
    //             currentTick + 1
    //         );
    //         currentTick += 1;
    //         let tickInfo = await uniV3Pool.ticks(currentTick);
    //         currentLiquidity = currentLiquidity.add(
    //             tickInfo.liquidityNet
    //         );
    //     } else {
    //         currentPrice = await tickMath.getSqrtRatioAtTick(
    //             currentTick
    //         );
    //         currentTick -= 1;
    //         let tickInfo = await uniV3Pool.ticks(currentTick);
    //         currentLiquidity = currentLiquidity.sub(
    //             tickInfo.liquidityNet
    //         );
    //     }
    // }
    // console.log(totalSwapAmount.toString());
}
