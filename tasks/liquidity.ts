import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { BigNumber } from "@ethersproject/bignumber";
import { BigNumberish, PopulatedTransaction } from "ethers";
import { ERC20Token, ISwapRouter, TickMathTest, TickMathTest__factory } from "../test/types";
import { abi as ICurvePool } from "../test/helpers/curvePoolABI.json";
import { abi as IWETH } from "../test/helpers/wethABI.json";
import { abi as IWSTETH } from "../test/helpers/wstethABI.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { abi as INonfungiblePositionManagerABI } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouterABI } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { randomBytes } from "crypto";
import { expect } from "chai";


task("swap-amount", "Calculates swap amount needed to shift price in the pool")
    .addParam("shift", "Price shift in ticks", undefined, types.int)
    .addParam("width", "Width of positions opened by LStrategy in ticks", undefined, types.int)
    .addParam("positiontick", "Tick representing lower bound of upper position", undefined, types.string)
    .addParam("pooltick", "Tick representing price in the pool. If not given, ", undefined, types.string)
    .addParam("liquidity", "Total pool liquidity", undefined, types.string)
    .addParam("verify", "Check if calculated amount is correct by simulalting swap in this state", false, types.boolean, true)
    .setAction(async ({ shift, width, positiontick:positionTickString, pooltick:poolTickString, liquidity:liqudityString, verify }, hre) => {
        if (width % 10 != 0) {
            console.error("Width should be multiple of 10 (tickSpacing)");
        } else if (+positionTickString % 10 != 0) {
            console.error(positionTickString)
            console.error("Position tick should be multiple of 10 (tickSpacing)");
        } else if ((+positionTickString > +poolTickString) || (+positionTickString + width / 2 < +poolTickString)) {
            console.error("Pool tick should be in bounds [positionTick; positionTick + width / 2]");
        } else {
            let context = await getContext(hre, verify);
            let { deltaXPriceDown, deltaYPriceUp } = await countSwapAmount(hre, shift, width, +positionTickString, +poolTickString, BigNumber.from(liqudityString), context);
            if (verify) {
                await simulateSwap(+poolTickString, shift, [deltaXPriceDown, deltaYPriceUp], hre, context);
            }
        }
    });

async function getContext(hre: HardhatRuntimeEnvironment, verify:boolean) {
    if (!verify) {
        return undefined;
    }
    const { getNamedAccounts, ethers } = hre;
    const { deployer, weth:wethAddress, wsteth:wstethAddress, uniswapV3Factory: uniswapV3FactoryAddress, uniswapV3Router, uniswapV3PositionManager } = await getNamedAccounts();
    
    const curvePool = await ethers.getContractAt(
        ICurvePool,
        "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022" // address of curve weth-wsteth
    );
    const weth: ERC20Token & any = await ethers.getContractAt(
        IWETH,
        wethAddress
    );
    const steth = await ethers.getContractAt(
        "ERC20Token",
        "0xae7ab96520de3a18e5e111b5eaab095312d7fe84"
    );
    const wsteth: ERC20Token & any = await ethers.getContractAt(
        IWSTETH,
        wstethAddress
    );

    let tokens: ERC20Token[] = [ wsteth, weth ];

    await weth.approve(
        curvePool.address,
        ethers.constants.MaxUint256
    );
    await steth.approve(
        wsteth.address,
        ethers.constants.MaxUint256
    );

    let wethMintAmount = BigNumber.from(10).pow(18).mul(800);
    await withSigner(randomAddress(hre), async (s) => {
        const tx: PopulatedTransaction = {
            to: weth.address,
            from: s.address,
            data: `0xd0e30db0`,
            gasLimit: BigNumber.from(10 ** 6),
            value: BigNumber.from(wethMintAmount),
        };
        const resp = await s.sendTransaction(tx);
        await resp.wait();;
        await weth.connect(s).transfer(deployer, wethMintAmount);
    }, hre);

    const options = { value: wethMintAmount.div(2) };
    await weth.withdraw(options.value);
    await curvePool.exchange(
        0,
        1,
        options.value,
        ethers.constants.Zero,
        options
    );
    await wsteth.wrap(wethMintAmount.mul(9).div(20));

    let uniswapV3Factory = await ethers.getContractAt(
        "IUniswapV3Factory",
        uniswapV3FactoryAddress
    );
    let poolAddress = await uniswapV3Factory.getPool(
        wsteth.address,
        weth.address,
        500
    );
    let uniV3Pool = await ethers.getContractAt(
        "IUniswapV3Pool",
        poolAddress
    );
    let swapRouter: ISwapRouter = await ethers.getContractAt(
        ISwapRouterABI,
        uniswapV3Router
    );
    let positionManager = await ethers.getContractAt(
        INonfungiblePositionManagerABI,
        uniswapV3PositionManager
    );

    const MathTickTest: TickMathTest__factory = await ethers.getContractFactory(
        "TickMathTest"
    );
    const tickMath: TickMathTest = await MathTickTest.deploy();
    await tickMath.deployed();

    return {
        positionManager,
        tickMath,
        uniV3Pool,
        tokens,
        deployer,
        swapRouter
    }
}
async function liquidityToY(
    currentTick: number,
    tickUpper: number,
    tickLower: number,
    liquidity: BigNumber,
    tickMath: TickMathTest,
    sqrtPriceX96?: BigNumber
) {
    if (sqrtPriceX96 == undefined) {
        sqrtPriceX96 = await tickMath.getSqrtRatioAtTick(currentTick);
    }
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
    tickMath: TickMathTest,
    sqrtPriceX96?: BigNumber
) {
    if (sqrtPriceX96 == undefined) {
        sqrtPriceX96 = await tickMath.getSqrtRatioAtTick(currentTick);
    }
    let tickUpperPriceX96 = await tickMath.getSqrtRatioAtTick(
        tickUpper
    );
    let smth = tickUpperPriceX96
        .sub(sqrtPriceX96)
        .mul(BigNumber.from(2).pow(96));
    return liquidity.mul(smth).div(tickUpperPriceX96.mul(sqrtPriceX96));
}

// splits liquidity between upper and lower positions, following LStrategy's logic
function splitByLiquidityRatio(targetTick: number, upperPositionTickLower:number, upperPositionTickUpper:number, liqudity:BigNumber) 
{
    let upperPositionMidTick = (upperPositionTickLower + upperPositionTickUpper) / 2;
    let liquidityRatio = Math.abs(targetTick - upperPositionMidTick);
    liquidityRatio = liquidityRatio / ((upperPositionTickUpper - upperPositionTickLower) / 2);
    let denom = 100000;
    return { lowerLiquidity: liqudity.mul(Math.round(denom * liquidityRatio)).div(denom), upperLiquidity: liqudity.mul(Math.round(denom * (1 - liquidityRatio))).div(denom) }

}
 
// counts changes in given position's token amounts when price changes 
async function tokenAmountsToShiftPosition(currentTick: number, newTick: number, tickLower: number, tickUpper: number, liqudity: BigNumber, tickMath: TickMathTest) {
    newTick = Math.max(newTick, tickLower);
    newTick = Math.min(newTick, tickUpper);

    let currentX = await liquidityToX(currentTick, tickUpper, tickLower, liqudity, tickMath);
    let newX = await liquidityToX(newTick, tickUpper, tickLower, liqudity, tickMath);
    let deltaX = newX.sub(currentX).abs();

    let currentY = await liquidityToY(currentTick, tickUpper, tickLower, liqudity, tickMath);
    let newY = await liquidityToY(newTick, tickUpper, tickLower, liqudity, tickMath);
    let deltaY = newY.sub(currentY).abs();
    return {deltaX, deltaY};
}

async function countSwapAmount(hre: HardhatRuntimeEnvironment, tickShift: number, positionWidth: number, upperPositionTickLower: number, poolTick: number, totalLiquidity: BigNumber, context: any | undefined) {
    const { ethers } = hre;
    const MathTickTest: TickMathTest__factory = await ethers.getContractFactory(
        "TickMathTest"
    );
    const tickMath: TickMathTest = await MathTickTest.deploy();
    await tickMath.deployed();
    
    // calculate tick bounds of our positions
    let lowerPositionTickLower = upperPositionTickLower - positionWidth / 2;
    let lowerPositionTickUpper = lowerPositionTickLower + positionWidth;
    let upperPositionTickUpper = upperPositionTickLower + positionWidth;

    // calculate token amounts from liquidity
    console.log("if pool tick is " + poolTick + ", there is");
    let {lowerLiquidity, upperLiquidity} = splitByLiquidityRatio(poolTick, upperPositionTickLower, upperPositionTickUpper, totalLiquidity);
    let lowerToX = await liquidityToX(poolTick, lowerPositionTickUpper, lowerPositionTickLower, lowerLiquidity, tickMath);
    let upperToX = await liquidityToX(poolTick, upperPositionTickUpper, upperPositionTickLower, upperLiquidity, tickMath);
    let lowerToY = await liquidityToY(poolTick, lowerPositionTickUpper, lowerPositionTickLower, lowerLiquidity, tickMath);
    let upperToY = await liquidityToY(poolTick, upperPositionTickUpper, upperPositionTickLower, upperLiquidity, tickMath);
    console.log(lowerToX.toString() + " of 0 and " + lowerToY.toString() + " of 1 in lower vault");
    console.log(upperToX.toString() + " of 0 and " + upperToY.toString() + " of 1 in upper vault");
    console.log(lowerToX.add(upperToX).toString() + " of 0 and " + lowerToY.add(upperToY).toString() + " of 1 total\n");
    
    // mid liquidity is a liquidity of utility position, used in integration part
    let midLiquidity = BigNumber.from("143542847431368536505");
    let uniV3PoolFeeDenominator = 1000000;
    let priceDownTick = poolTick - tickShift;
    let priceUpTick = poolTick + tickShift;
    if (context != undefined) {
        context.lowerPositionTickLower = lowerPositionTickLower;
        context.lowerPositionTickUpper = lowerPositionTickUpper;
        context.upperPositionTickLower = upperPositionTickLower;
        context.upperPositionTickUpper = upperPositionTickUpper;
        context.lowerToX = lowerToX;
        context.lowerToY = lowerToY;
        context.upperToX = upperToX;
        context.upperToY = upperToY;
        context.midLiquidity = midLiquidity;
        context.uniV3PoolFeeDenominator = uniV3PoolFeeDenominator;
    }

    // tokens needed to swap in each position if price goes down
    let { deltaX:priceDownDeltaXLower, deltaY:priceDownDeltaYLower } = await tokenAmountsToShiftPosition(poolTick, priceDownTick, lowerPositionTickLower, lowerPositionTickUpper, lowerLiquidity, tickMath);
    let { deltaX:priceDownDeltaXUpper, deltaY:priceDownDeltaYUpper } = await tokenAmountsToShiftPosition(poolTick, priceDownTick, upperPositionTickLower, upperPositionTickUpper, upperLiquidity, tickMath);
    let { deltaX:priceDownDeltaXMid, deltaY:priceDownDeltaYMid } = await tokenAmountsToShiftPosition(poolTick, priceDownTick, -887220, 887220, midLiquidity, tickMath);
    let priceDownDeltaX = priceDownDeltaXLower.add(priceDownDeltaXUpper);
    let priceDownDeltaY = priceDownDeltaYLower.add(priceDownDeltaYUpper);
    let priceDownDeltaXAllPositions = priceDownDeltaX.add(priceDownDeltaXMid);
    let priceDownDeltaYAllPositions = priceDownDeltaY.add(priceDownDeltaYMid);

    // tokens needed to swap in each position if price goes up
    let { deltaX:priceUpDeltaXLower, deltaY:priceUpDeltaYLower } = await tokenAmountsToShiftPosition(poolTick, priceUpTick, lowerPositionTickLower, lowerPositionTickUpper, lowerLiquidity, tickMath);
    let { deltaX:priceUpDeltaXUpper, deltaY:priceUpDeltaYUpper } = await tokenAmountsToShiftPosition(poolTick, priceUpTick, upperPositionTickLower, upperPositionTickUpper, upperLiquidity, tickMath);
    let { deltaX:priceUpDeltaXMid, deltaY:priceUpDeltaYMid } = await tokenAmountsToShiftPosition(poolTick, priceUpTick, -887220, 887220, midLiquidity, tickMath);
    let priceUpDeltaX = priceUpDeltaXLower.add(priceUpDeltaXUpper);
    let priceUpDeltaY = priceUpDeltaYLower.add(priceUpDeltaYUpper);
    let priceUpDeltaXAllPositions = priceUpDeltaX.add(priceUpDeltaXMid);
    let priceUpDeltaYAllPositions = priceUpDeltaY.add(priceUpDeltaYMid);

    // multiply by fee
    priceDownDeltaXAllPositions = priceDownDeltaXAllPositions.mul(uniV3PoolFeeDenominator + 500).div(uniV3PoolFeeDenominator);
    priceUpDeltaYAllPositions = priceUpDeltaYAllPositions.mul(uniV3PoolFeeDenominator + 500).div(uniV3PoolFeeDenominator);


    console.log("To lower price for " + tickShift + " ticks, you need to swap at least");
    console.log(priceDownDeltaX.toString() + " of 0 for " + priceDownDeltaY.abs().toString() + " of 1");
    console.log("To higher price for " + tickShift + " ticks, you need to swap at least");
    console.log(priceUpDeltaY.toString() + " of 1 for " + priceUpDeltaX.abs().toString() + " of 0\n");

    return { deltaXPriceDown: priceDownDeltaXAllPositions, deltaYPriceUp: priceUpDeltaYAllPositions };
}

const withSigner = async (
    address: string,
    f: (signer: SignerWithAddress) => Promise<void>,
    hre: HardhatRuntimeEnvironment
) => {
    const signer = await addSigner(address, hre);
    await f(signer);
    await removeSigner(address, hre);
};
const addSigner = async (
    address: string,
    hre: HardhatRuntimeEnvironment
): Promise<SignerWithAddress> => {
    let { network, ethers } = hre;
    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address],
    });
    await network.provider.send("hardhat_setBalance", [
        address,
        "0x1000000000000000000",
    ]);
    return await ethers.getSigner(address);
};
const removeSigner = async (address: string,
    hre: HardhatRuntimeEnvironment) => {
    let { network } = hre;
    await network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [address],
    });
};
const randomAddress = (hre: HardhatRuntimeEnvironment) => {
    let { ethers } = hre;
    const id = randomBytes(32).toString("hex");
    const privateKey = "0x" + id;
    const wallet = new ethers.Wallet(privateKey);
    return wallet.address;
};
async function uniSwapTokensGivenInput(
    router: ISwapRouter,
    tokens: ERC20Token[],
    fee: number,
    zeroForOne: boolean,
    amount: BigNumberish,
    hre: HardhatRuntimeEnvironment,
    provider?: string
) {
    if (provider == undefined) {
        provider = randomAddress(hre);
    }
    let tokenIndex = zeroForOne ? 1 : 0;
    let swapParams = {
        tokenIn: tokens[tokenIndex].address,
        tokenOut: tokens[1 ^ tokenIndex].address,
        fee: fee,
        recipient: provider,
        deadline: hre.ethers.constants.MaxUint256,
        amountIn: amount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0,
    };

    let amountOut: BigNumber = BigNumber.from(0);
    await withSigner(provider, async (signer) => {
        await tokens[tokenIndex]
            .connect(signer)
            .approve(router.address, amount);
        amountOut = await router
            .connect(signer)
            .callStatic.exactInputSingle(swapParams);
        await router.connect(signer).exactInputSingle(swapParams);
    }, hre);
    return amountOut;
}
async function mintPosition(tokens: ERC20Token[], amounts: BigNumber[], ticks: number[], recipient: string, hre: HardhatRuntimeEnvironment, context: any) {
    const mintParams = {
        token0: tokens[0].address,
        token1: tokens[1].address,
        fee: 500,
        tickLower: ticks[0],
        tickUpper: ticks[1],
        amount0Desired: amounts[0],
        amount1Desired: amounts[1],
        amount0Min: 0,
        amount1Min: 0,
        recipient: recipient,
        deadline: hre.ethers.constants.MaxUint256,
    };

    for (let token of tokens) {
        await token
            .approve(
                context.positionManager.address,
                hre.ethers.constants.MaxUint256
            );
    }

    const result = await context.positionManager
        .callStatic.mint(mintParams);
    await context.positionManager.mint(mintParams);
    return result;
}

export async function uniSwapTokensGivenOutput(
    router: ISwapRouter,
    tokens: ERC20Token[],
    fee: number,
    zeroForOne: boolean,
    amount: BigNumberish,
    hre: HardhatRuntimeEnvironment,
    provider?: string
) {
    const MAXIMUM_TO_SPEND = BigNumber.from(10).pow(21);
    if (provider == undefined) {
        provider = randomAddress(hre);
    }
    let tokenIndex = zeroForOne ? 1 : 0;
    let swapParams = {
        tokenIn: tokens[tokenIndex].address,
        tokenOut: tokens[1 ^ tokenIndex].address,
        fee: fee,
        recipient: provider,
        deadline: hre.ethers.constants.MaxUint256,
        amountOut: amount,
        amountInMaximum: MAXIMUM_TO_SPEND,
        sqrtPriceLimitX96: 0,
    };

    let amountIn = BigNumber.from(0);
    await withSigner(provider, async (signer) => {
        await tokens[tokenIndex]
            .connect(signer)
            .approve(router.address, MAXIMUM_TO_SPEND);
        amountIn = await router
            .connect(signer)
            .callStatic.exactOutputSingle(swapParams);
        await router.connect(signer).exactOutputSingle(swapParams);
        await tokens[tokenIndex].connect(signer).approve(router.address, 0);
    }, hre);
    return amountIn;
}

async function simulateSwap(targetTick: number, tickShift: number,  swapAmounts: BigNumber[], hre: HardhatRuntimeEnvironment, context: any) {
    let { ethers } = hre;
    let { uniV3Pool, swapRouter, tokens, positionManager, deployer, tickMath, lowerPositionTickLower, lowerPositionTickUpper, upperPositionTickLower, upperPositionTickUpper, lowerToX, lowerToY, upperToX, upperToY, midLiquidity, uniV3PoolFeeDenominator} = context;
    
    console.log("Checking results:");
    
    // on block number 13268999, our univ3 pool has one active position: from -100 to 100 
    // we create two more positions to lengthen it
    console.log("··mint utility positions");
    let amountLower = await liquidityToY(-100, -100, -887220, midLiquidity, tickMath);
    await mintPosition(tokens, [BigNumber.from(0), amountLower], [-887220, -100], deployer, hre, context);
    let amountUpper = await liquidityToX(100, 887220, 100, midLiquidity, tickMath);
    await mintPosition(tokens, [amountUpper, BigNumber.from(0)], [100, 887220], deployer, hre, context);

    // set pool's tick to target
    let poolTick = (await uniV3Pool.slot0()).tick;
    console.log("··setting up pool");
    console.log("····pool's tick is " + poolTick);
    console.log("····shift price to exact start of " + poolTick);
    let yAmount = await liquidityToY(poolTick, poolTick + 1, poolTick, midLiquidity, tickMath, (await uniV3Pool.slot0()).sqrtPriceX96);
    await uniSwapTokensGivenOutput(swapRouter, tokens, 500, false, yAmount.sub("1000000000000"), hre, deployer); 
    console.log("····shift tick from " + poolTick + " to " + targetTick);
    let tokenAmounts = await tokenAmountsToShiftPosition(poolTick, targetTick, -887220, 887220, BigNumber.from("143542847431368536505"), tickMath);
    let swapZeroForOne = targetTick > poolTick;
    for (let token of tokens) {
        await token
            .approve(
                swapRouter.address,
                ethers.constants.MaxUint256
            );
    }
    await uniSwapTokensGivenOutput(swapRouter, tokens, 500, swapZeroForOne, swapZeroForOne ? tokenAmounts.deltaX : tokenAmounts.deltaY, hre, deployer); 


    // minting LStrategy's univ3 positions
    console.log("··minting lower and upper positions");
    const resultLower = await mintPosition(tokens, [lowerToX, lowerToY], [lowerPositionTickLower, lowerPositionTickUpper], deployer, hre, context);
    let lowerStats = await positionManager.positions(resultLower.tokenId);
    console.log("····lower position's liquidity is " + lowerStats.liquidity.toString());
    const resultUpper = await mintPosition(tokens, [upperToX, upperToY], [upperPositionTickLower, upperPositionTickUpper], deployer, hre, context);
    let upperStats = await positionManager.positions(resultUpper.tokenId);
    console.log("····upper position's liquidity is " + upperStats.liquidity.toString());
    console.log("··pool is set up");
    console.log("····tick is " + (await uniV3Pool.slot0()).tick);
    
    // check if first swap is correct
    console.log("··swapping " + swapAmounts[0].toString() + " of 0");
    let out = await uniSwapTokensGivenInput(swapRouter, tokens, 500, false, swapAmounts[0], hre, deployer);  
    console.log("····post-swap tick is " + (await uniV3Pool.slot0()).tick);
    expect(Math.abs((await uniV3Pool.slot0()).tick - targetTick)).to.be.eq(tickShift);

    // return tick to target
    console.log("··unswap");
    await uniSwapTokensGivenInput(swapRouter, tokens, 500, true, out.mul(uniV3PoolFeeDenominator + 500).div(uniV3PoolFeeDenominator), hre, deployer);  
    console.log("····tick is " + (await uniV3Pool.slot0()).tick);
    
    // check if second swap is correct
    console.log("··swapping " + swapAmounts[1].toString() + " of 1");
    out = await uniSwapTokensGivenInput(swapRouter, tokens, 500, true, swapAmounts[1], hre, deployer);  
    console.log("····post-swap tick is " + (await uniV3Pool.slot0()).tick);
    expect(Math.abs((await uniV3Pool.slot0()).tick - targetTick)).to.be.eq(tickShift);
}