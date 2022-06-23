import { BigNumber } from "@ethersproject/bignumber";
import { Contract } from "ethers";
import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { TickMath } from "@uniswap/v3-sdk";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import JSBI from "jsbi";
import { withSigner } from "./sign";
import { sqrt } from "@uniswap/sdk-core";

export type Context = {
    protocolGovernance: Contract;
    swapRouter: Contract;
    positionManager: Contract;
    LStrategy: Contract;
    weth: Contract;
    wsteth: Contract;
    admin: SignerWithAddress;
    deployer: SignerWithAddress;
    mockOracle: Contract;
    erc20RootVault: Contract;
};

export type StrategyStats = {
    erc20token0: BigNumber;
    erc20token1: BigNumber;
    lowerVaultTokenOwed0: BigNumber;
    lowerVaultTokenOwed1: BigNumber;
    lowerVaultLiquidity: BigNumber;
    upperVaultTokenOwed0: BigNumber;
    upperVaultTokenOwed1: BigNumber;
    upperVaultLiquidity: BigNumber;
    currentTick: BigNumber;
};

export const preparePush = async ({
    hre,
    context,
    vault,
    tickLower = -887220,
    tickUpper = 887220,
    wethAmount = BigNumber.from(10).pow(9),
    wstethAmount = BigNumber.from(10).pow(9),
}: {
    hre: HardhatRuntimeEnvironment;
    context: Context
    vault: any;
    tickLower?: number;
    tickUpper?: number;
    wethAmount?: BigNumber;
    wstethAmount?: BigNumber;
}) => {
    const { ethers } = hre;
    const mintParams = {
        token0: context.wsteth.address,
        token1: context.weth.address,
        fee: 500,
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Desired: wstethAmount,
        amount1Desired: wethAmount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: context.deployer.address,
        deadline: ethers.constants.MaxUint256,
    };
    const result = await context.positionManager.callStatic.mint(
        mintParams
    );
    await context.positionManager.mint(mintParams);
    await context.positionManager.functions[
        "safeTransferFrom(address,address,uint256)"
    ](context.deployer.address, vault, result.tokenId);
};


export const getTvl = async (
    hre: HardhatRuntimeEnvironment,
    address: string
) => {
    const { ethers } = hre;
    let vault = await ethers.getContractAt("IVault", address);
    let tvls = await vault.tvl();
    return tvls;
};


export const getUniV3Tick = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    let pool = await getPool(hre, context);
    const currentState = await pool.slot0();
    return BigNumber.from(currentState.tick);
};


export const makeSwap = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    const { ethers } = hre;
    let erc20Vault = await context.LStrategy.erc20Vault();
    let vault = await ethers.getContractAt(
        "IVault",
        erc20Vault
    );

    let erc20Tvl = await vault.tvl();
    let tokens = [context.wsteth, context.weth];
    let delta = erc20Tvl[0][0].sub(erc20Tvl[0][1]);

    if (delta.lt(BigNumber.from(-1))) {
        await swapTokens(
            hre,
            context,
            erc20Vault,
            erc20Vault,
            tokens[1],
            tokens[0],
            delta.div(2).mul(-1)
        );
    }

    if (delta.gt(BigNumber.from(1))) {
        await swapTokens(
            hre,
            context,
            erc20Vault,
            erc20Vault,
            tokens[0],
            tokens[1],
            delta.div(2)
        );
    }
};

export const swapOnCowswap = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
) => {
    const { ethers } = hre;
    await context.LStrategy
        .connect(context.admin)
        .postPreOrder(ethers.constants.Zero);
    const preOrder = await context.LStrategy.preOrder();
    if (preOrder.tokenIn == context.weth.address) {
        await swapWethToWsteth(hre, context, preOrder.amountIn, preOrder.minAmountOut);
    } else {
        await swapWstethToWeth(hre, context, preOrder.amountIn, preOrder.minAmountOut);
    }
};

const swapWethToWsteth = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    amountIn: BigNumber,
    minAmountOut: BigNumber,
) => {
    const erc20 = await context.LStrategy.erc20Vault();
    const { deployer, wsteth, weth } = context;
    const { ethers } = hre;
    let erc20address = await context.LStrategy.erc20Vault();
    const erc20Vault = await ethers.getContractAt(
        "ERC20Vault",
        erc20address,
    );
    const pool = await getPool(hre, context);
    const currentTick = (await pool.slot0()).tick;
    const price = BigNumber.from(TickMath.getSqrtRatioAtTick(currentTick).toString());
    const denominator = BigNumber.from(2).pow(96);
    const balance = await wsteth.balanceOf(deployer.address);
    let expectedOut = amountIn.mul(denominator).div(price);
    if (expectedOut.gt(balance)) {
        console.log("Insufficient balance of weth");
        expectedOut = balance;
    }
    if (expectedOut.lt(minAmountOut)) {
        return;
    }
    await withSigner(hre, erc20, async (signer) => {
        await weth.connect(signer).transfer(deployer.address, amountIn);
    });
    await wsteth.connect(deployer).transfer(erc20, expectedOut);
};

const swapWstethToWeth = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    amountIn: BigNumber,
    minAmountOut: BigNumber
) => {
    const erc20 = await context.LStrategy.erc20Vault();
    const { deployer, wsteth, weth } = context;
    const { ethers } = hre;
    let erc20address = await context.LStrategy.erc20Vault();
    const erc20Vault = await ethers.getContractAt(
        "ERC20Vault",
        erc20address,
    );
    const pool = await getPool(hre, context);
    const currentTick = (await pool.slot0()).tick;
    const price = BigNumber.from(TickMath.getSqrtRatioAtTick(currentTick).toString());
    const denominator = BigNumber.from(2).pow(96);
    const balance = await weth.balanceOf(deployer.address);
    let expectedOut = amountIn.mul(price).div(denominator);
    if (expectedOut.gt(balance)) {
        console.log("Insufficient balance of weth");
        expectedOut = balance;
    }
    if (expectedOut.lt(minAmountOut)) {
        return;
    }
    await withSigner(hre, erc20, async (signer) => {
        await wsteth.connect(signer).transfer(deployer.address, amountIn);
    });
    await weth.connect(deployer).transfer(erc20, expectedOut);
};

export const swapTokens = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    senderAddress: string,
    recipientAddress: string,
    tokenIn: Contract,
    tokenOut: Contract,
    amountIn: BigNumber
) => {
    const { ethers } = hre;
    await withSigner(hre, senderAddress, async (senderSigner) => {
        await tokenIn
            .connect(senderSigner)
            .approve(
                context.swapRouter.address,
                ethers.constants.MaxUint256
            );
        let params = {
            tokenIn: tokenIn.address,
            tokenOut: tokenOut.address,
            fee: 500,
            recipient: recipientAddress,
            deadline: ethers.constants.MaxUint256,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
        };
        await context.swapRouter
            .connect(senderSigner)
            .exactInputSingle(params);
    });
};

export const stringToSqrtPriceX96 = (x: string) => {
    let sPrice = Math.sqrt(parseFloat(x));
    let resPrice = BigNumber.from(Math.round(sPrice * (2**30))).mul(BigNumber.from(2).pow(66));
    return resPrice;
};

export const stringToPriceX96 = (x: string) => {
    let sPrice = parseFloat(x);
    let resPrice = BigNumber.from(Math.round(sPrice * (2**30))).mul(BigNumber.from(2).pow(66));
    return resPrice;
};

export const getTick = (x: BigNumber) => {
    return BigNumber.from(TickMath.getTickAtSqrtRatio(JSBI.BigInt(x)));
};

export const getPool = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    const { ethers } = hre;
    let lowerVault = await ethers.getContractAt(
        "IUniV3Vault",
        await context.LStrategy.lowerVault()
    );
    let pool = await ethers.getContractAt(
        "IUniswapV3Pool",
        await lowerVault.pool()
    );
    return pool;
};

const getExpectedRatio = async (context: Context) => {
    const tokens = [context.wsteth.address, context.weth.address];
    const targetPriceX96 = await context.LStrategy.targetPrice(
        tokens[0],
        tokens[1],
        await context.LStrategy.tradingParams()
    );
    const sqrtTargetPriceX96 = BigNumber.from(
        sqrt(JSBI.BigInt(targetPriceX96)).toString()
    );
    const targetTick = TickMath.getTickAtSqrtRatio(
        JSBI.BigInt(
            sqrtTargetPriceX96
                .mul(BigNumber.from(2).pow(48))
                .toString()
        )
    );
    return await context.LStrategy.targetUniV3LiquidityRatio(
        targetTick
    );
};

const getVaultsLiquidityRatio = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    const { ethers } = hre;
    let lowerVault = await ethers.getContractAt(
        "UniV3Vault",
        await context.LStrategy.lowerVault()
    );
    let upperVault = await ethers.getContractAt(
        "UniV3Vault",
        await context.LStrategy.upperVault()
    );
    const [, , , , , , , lowerVaultLiquidity, , , ,] =
        await context.positionManager.positions(
            await lowerVault.uniV3Nft()
        );
    const [, , , , , , , upperVaultLiquidity, , , ,] =
        await context.positionManager.positions(
            await upperVault.uniV3Nft()
        );
    const total = lowerVaultLiquidity.add(upperVaultLiquidity);
    const DENOMINATOR = await context.LStrategy.DENOMINATOR();
    return DENOMINATOR.sub(
        lowerVaultLiquidity.mul(DENOMINATOR).div(total)
    );
};

export const checkUniV3Balance = async(hre: HardhatRuntimeEnvironment, context: Context) => {

    let [neededRatio, _] = await getExpectedRatio(context);
    let currentRatio = await getVaultsLiquidityRatio(hre, context);
    return(neededRatio.sub(currentRatio).abs().lt(BigNumber.from(10).pow(7).mul(5)));

};

export const getStrategyStats = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    const pool = await getPool(hre, context);
    const currentTick = (await pool.slot0()).tick;
    const { ethers } = hre;
    const lowerVault = await ethers.getContractAt(
        "IUniV3Vault",
        await context.LStrategy.lowerVault()
    );
    const upperVault = await ethers.getContractAt(
        "IUniV3Vault",
        await context.LStrategy.upperVault()
    );
    const [, , , , , , , lowerVaultLiquidity, , , lowerTokensOwed0, lowerTokensOwed1] =
        await context.positionManager.positions(
            await lowerVault.uniV3Nft()
        );
    const [, , , , , , , upperVaultLiquidity, , , upperTokensOwed0, upperTokensOwed1] =
        await context.positionManager.positions(
            await upperVault.uniV3Nft()
        );
    const erc20Vault = await context.LStrategy.erc20Vault();
    const vault = await ethers.getContractAt(
        "IVault",
        erc20Vault
    );

    const [erc20Tvl, ] = await vault.tvl();
    const [lowerTvlLeft, upperTvlRight] = await lowerVault.tvl();
    return {
        erc20token0: erc20Tvl[0],
        erc20token1: erc20Tvl[1],
        lowerVaultTokenOwed0: lowerTokensOwed0,
        lowerVaultTokenOwed1: lowerTokensOwed1,
        lowerVaultLiquidity: lowerVaultLiquidity,
        upperVaultTokenOwed0: upperTokensOwed0,
        upperVaultTokenOwed1: upperTokensOwed1,
        upperVaultLiquidity: upperVaultLiquidity,
        currentTick: currentTick,
    } as StrategyStats;
};
