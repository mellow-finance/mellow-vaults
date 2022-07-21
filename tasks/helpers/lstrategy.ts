import { BigNumber } from "@ethersproject/bignumber";
import { BigNumberish, Contract } from "ethers";
import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { TickMath } from "@uniswap/v3-sdk";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import JSBI from "jsbi";
import { withSigner } from "./sign";
import { sqrt } from "@uniswap/sdk-core";
import { toObject } from "./utils";
import { equals } from "ramda";
import { mint} from "./utils";
import { addSigner} from "./sign";
import { expect } from "chai";

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
    lowerToken0: BigNumber;
    lowerToken1: BigNumber;
    lowerLeftTick: number;
    lowerRightTick: number;
    upperToken0: BigNumber;
    upperToken1: BigNumber;
    upperLeftTick: number;
    upperRightTick: number;
    currentPrice: string;
    currentTick: number,
    totalToken0: BigNumber;
    totalToken1: BigNumber;
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


export const getUniV3Price = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    let pool = await getPool(hre, context);
    const { sqrtPriceX96 } = await pool.slot0();
    return sqrtPriceX96.mul(sqrtPriceX96).div(BigNumber.from(2).pow(96));
};

export const swapOnCowswap = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    wstethAmountInPool: BigNumber,
    wethAmountInPool: BigNumber,
    curvePool: any,
    wethContract: any,
    wstethContract: any,
    stethContract: any
) => {

    const { ethers } = hre;
    await context.LStrategy
        .connect(context.admin)
        .postPreOrder(ethers.constants.Zero);
    const preOrder = await context.LStrategy.preOrder();
    if (preOrder.tokenIn == context.weth.address) {
        await swapWethToWsteth(hre, context, preOrder.amountIn, preOrder.minAmountOut, wstethAmountInPool, wethAmountInPool, curvePool, wstethContract, wethContract, stethContract);
    } else {
        await swapWstethToWeth(hre, context, preOrder.amountIn, preOrder.minAmountOut, wstethAmountInPool, wethAmountInPool, curvePool, wstethContract, wethContract, stethContract);
    }
};

export const getTick = (x: BigNumber) => {
    return BigNumber.from(TickMath.getTickAtSqrtRatio(JSBI.BigInt(x)));
};

const mintForPool = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    toMintEth: BigNumber,
    toMintSteth: BigNumber,
    wethContract: any,
    wstethContract: any,
    stethContract: any,
    curvePool: any
) => {

    // gas cover
    toMintEth = toMintEth.add(BigNumber.from(10).pow(17));

    const { ethers, getNamedAccounts } = hre;

    const {deployer} = await getNamedAccounts();
    const deployerSigned = await addSigner(hre, deployer);

    let mintedEth = await ethers.provider.getBalance(deployerSigned.address);
    let mintedSteth = await stethContract.balanceOf(deployerSigned.address);

    while (toMintEth.gt(BigNumber.from(0))) {

        let mintNow = BigNumber.from(10).pow(21);
        if (mintNow.gt(toMintEth)) {
            mintNow = toMintEth;
        }

        await mint(hre, "WETH", deployerSigned.address, mintNow);
        await wethContract.withdraw(mintNow);

        toMintEth = toMintEth.sub(mintNow);
    }

    while (toMintSteth.gt(BigNumber.from(0))) {
        
        let mintNow = BigNumber.from(10).pow(21);
        if (mintNow.gt(toMintSteth)) {
            mintNow = toMintSteth;
        }
        await mint(hre, "WETH", deployerSigned.address, mintNow);
        await wethContract.withdraw(mintNow);
        await stethContract.submit(deployerSigned.address, {value : mintNow});

        toMintSteth = toMintSteth.sub(mintNow);
    }

    mintedEth = (await ethers.provider.getBalance(deployerSigned.address)).sub(mintedEth);
    mintedSteth = (await stethContract.balanceOf(deployerSigned.address)).sub(mintedSteth);

    await stethContract.approve(curvePool.address, ethers.constants.MaxUint256);
    await curvePool.add_liquidity([mintedEth, mintedSteth], 0, {value : mintedEth});
    
}

const exchange = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    amountIn: BigNumber,
    wstethAmountInPool: BigNumber,
    wethAmountInPool: BigNumber,
    curvePool: any,
    wstethContract: any,
    wethContract: any,
    stethContract: any,
    wstethToWeth: boolean
) => {

    const { ethers } = hre;

    const steth = await ethers.getContractAt(
        "ERC20Token",
        "0xae7ab96520de3a18e5e111b5eaab095312d7fe84"
    );  
    
    const poolEthBalance = await ethers.provider.getBalance(curvePool.address);
    const poolStethBalance = await steth.balanceOf(curvePool.address);

    // poolEthBalance * wstethAmountInPool = poolStethBalance * wethAmountInPool

    let firstMultiplier = poolEthBalance.mul(wstethAmountInPool);
    let secondMuliplier = poolStethBalance.mul(wethAmountInPool);

    let newPoolEth = poolEthBalance;
    let newPoolSteth = poolStethBalance;

    if (firstMultiplier.lt(secondMuliplier)) {
        newPoolEth = secondMuliplier.div(wstethAmountInPool);
    }
    if (secondMuliplier.lt(firstMultiplier)) {
        newPoolSteth = firstMultiplier.div(wethAmountInPool);
    }

    await mintForPool(hre, context, newPoolEth.sub(poolEthBalance), newPoolSteth.sub(poolStethBalance), wethContract, wstethContract, stethContract, curvePool);

    firstMultiplier = (await ethers.provider.getBalance(curvePool.address)).mul(wstethAmountInPool);
    secondMuliplier = (await steth.balanceOf(curvePool.address)).mul(wethAmountInPool);

    const delta = firstMultiplier.sub(secondMuliplier).abs();
    expect(delta.mul(1000)).to.be.lt(firstMultiplier);

    let from = 0;
    let to = 1;
    let val = amountIn.mul(newPoolEth).div(wethAmountInPool);

    if (wstethToWeth) {
        from = 1;
        to = 0;
        val = BigNumber.from(0);
    }

    // proportional to the our situation in the pool
    let result = await curvePool.callStatic.exchange(from, to, amountIn.mul(newPoolEth).div(wethAmountInPool), 0, {value: val});

    // return adjusted
    return result.mul(wethAmountInPool).div(newPoolEth);

}

const swapWethToWsteth = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    amountIn: BigNumber,
    minAmountOut: BigNumber,
    wstethAmountInPool: BigNumber,
    wethAmountInPool: BigNumber,
    curvePool: any,
    wstethContract: any,
    wethContract: any,
    stethContract: any
) => {

    const { ethers } = hre;

    const erc20 = await context.LStrategy.erc20Vault();
    const { deployer, wsteth, weth} = context;
    const balance = await wsteth.balanceOf(deployer.address);

    let expectedOut = await exchange(hre, context, amountIn, wstethAmountInPool, wethAmountInPool, curvePool, wstethContract, wethContract, stethContract, false);

    if (expectedOut.gt(balance)) {
        expectedOut = balance;
    }
    if (expectedOut.lt(minAmountOut)) {
        console.log("Expected out less than minAmountOut weth=>wsteth");
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
    minAmountOut: BigNumber,
    wstethAmountInPool: BigNumber,
    wethAmountInPool: BigNumber,
    curvePool: any,
    wstethContract: any,
    wethContract: any,
    stethContract: any
) => {

    const { ethers } = hre;

    const erc20 = await context.LStrategy.erc20Vault();
    const { deployer, wsteth, weth } = context;
    const balance = await weth.balanceOf(deployer.address);

    let expectedOut = await exchange(hre, context, amountIn, wstethAmountInPool, wethAmountInPool, curvePool, wstethContract, wethContract, stethContract, true);

    if (expectedOut.gt(balance)) {
        expectedOut = balance;
    }
    if (expectedOut.lt(minAmountOut)) {
        console.log("Expected out less than minAmountOut wsteth=>weth");
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
    // console.log("token: ", await tokenIn.name());
    // console.log("amount: ", amountIn.toString());
    // console.log("balance: ", (await tokenIn.balanceOf(senderAddress)).toString());
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
    const targetPriceX96 = await context.LStrategy.getTargetPriceX96(
        tokens[0],
        tokens[1],
        await context.LStrategy.tradingParams()
    );
    const sqrtTargetPriceX48 = BigNumber.from(
        sqrt(JSBI.BigInt(targetPriceX96)).toString()
    );
    const targetTick = TickMath.getTickAtSqrtRatio(
        JSBI.BigInt(
            sqrtTargetPriceX48
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

export const priceX96ToFloat = (priceX96: BigNumber) => {
    const result = priceX96.mul(100_000).div(BigNumber.from(2).pow(96));
    const mod = result.mod(100_000);
    const n = result.div(100_000).toString();
    if (mod.lt(10)) {
        return n + ".0000" + mod.toString();
    }
    if (mod.lt(100)) {
        return n + ".000" + mod.toString();
    }
    if (mod.lt(1000)) {
        return n + ".00" + mod.toString();
    }
    if (mod.lt(10_000)) {
        return n + ".0" + mod.toString();
    }
    return n + "." + mod.toString();
}

export const getStrategyStats = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    const pool = await getPool(hre, context);
    const { tick, sqrtPriceX96 } = await pool.slot0();
    const { ethers } = hre;
    const lowerVault = await ethers.getContractAt(
        "IUniV3Vault",
        await context.LStrategy.lowerVault()
    );
    const upperVault = await ethers.getContractAt(
        "IUniV3Vault",
        await context.LStrategy.upperVault()
    );
    const erc20Vault = await context.LStrategy.erc20Vault();
    const vault = await ethers.getContractAt(
        "IVault",
        erc20Vault
    );

    const positionLower = await context.positionManager.positions(await lowerVault.uniV3Nft());
    const positionUpper = await context.positionManager.positions(await upperVault.uniV3Nft());

    const [erc20Tvl, ] = await vault.tvl();
    const [minTvlLower, ] = await lowerVault.tvl();
    const [minTvlUpper, ] = await upperVault.tvl();
    return {
        erc20token0: erc20Tvl[0],
        erc20token1: erc20Tvl[1],
        lowerToken0: minTvlLower[0],
        lowerToken1: minTvlLower[1],
        lowerLeftTick: positionLower.tickLower,
        lowerRightTick: positionLower.tickUpper,
        upperToken0: minTvlUpper[0],
        upperToken1: minTvlUpper[1],
        upperLeftTick: positionUpper.tickLower,
        upperRightTick: positionUpper.tickUpper,
        currentPrice: priceX96ToFloat(sqrtPriceX96.mul(sqrtPriceX96).div(BigNumber.from(2).pow(96))),
        currentTick: tick,
        totalToken0: erc20Tvl[0].add(minTvlLower[0]).add(minTvlUpper[0]),
        totalToken1: erc20Tvl[1].add(minTvlLower[1]).add(minTvlUpper[1]),
    } as StrategyStats;
};

export const setupVault = async (
    hre: HardhatRuntimeEnvironment,
    expectedNft: number,
    contractName: string,
    {
        createVaultArgs,
        delayedStrategyParams,
        strategyParams,
        delayedProtocolPerVaultParams,
    }: {
        createVaultArgs: any[];
        delayedStrategyParams?: { [key: string]: any };
        strategyParams?: { [key: string]: any };
        delayedProtocolPerVaultParams?: { [key: string]: any };
    }
) => {
    delayedStrategyParams ||= {};
    const { deployments, ethers, getNamedAccounts } = hre;
    const { log, execute, read } = deployments;
    const { deployer, admin } = await getNamedAccounts();
    const TRANSACTION_GAS_LIMITS = {
        maxFeePerGas: ethers.BigNumber.from(90000000000),
        maxPriorityFeePerGas: ethers.BigNumber.from(40000000000),
    }
    const currentNft = await read("VaultRegistry", "vaultsCount");
    if (currentNft <= expectedNft) {
        log(`Deploying ${contractName.replace("Governance", "")}...`);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
                ...TRANSACTION_GAS_LIMITS
            },
            "createVault",
            ...createVaultArgs
        );
        log(`Done, nft = ${expectedNft}`);
    } else {
        log(
            `${contractName.replace(
                "Governance",
                ""
            )} with nft = ${expectedNft} already deployed`
        );
    }
    if (strategyParams) {
        const currentParams = await read(
            contractName,
            "strategyParams",
            expectedNft
        );

        if (!equals(strategyParams, toObject(currentParams))) {
            log(`Setting Strategy params for ${contractName}`);
            log(strategyParams);
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS
                },
                "setStrategyParams",
                expectedNft,
                strategyParams
            );
        }
    }
    let strategyTreasury;
    try {
        const data = await read(
            contractName,
            "delayedStrategyParams",
            expectedNft
        );
        strategyTreasury = data.strategyTreasury;
    } catch {
        return;
    }

    if (strategyTreasury !== delayedStrategyParams.strategyTreasury) {
        log(`Setting delayed strategy params for ${contractName}`);
        log(delayedStrategyParams);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
                ...TRANSACTION_GAS_LIMITS
            },
            "stageDelayedStrategyParams",
            expectedNft,
            delayedStrategyParams
        );
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
                ...TRANSACTION_GAS_LIMITS
            },
            "commitDelayedStrategyParams",
            expectedNft
        );
    }
    if (delayedProtocolPerVaultParams) {
        const params = await read(
            contractName,
            "delayedProtocolPerVaultParams",
            expectedNft
        );
        if (!equals(toObject(params), delayedProtocolPerVaultParams)) {
            log(
                `Setting delayed protocol per vault params for ${contractName}`
            );
            log(delayedProtocolPerVaultParams);

            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS
                },
                "stageDelayedProtocolPerVaultParams",
                expectedNft,
                delayedProtocolPerVaultParams
            );
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS
                },
                "commitDelayedProtocolPerVaultParams",
                expectedNft
            );
        }
    }
};

export const combineVaults = async (
    hre: HardhatRuntimeEnvironment,
    expectedNft: number,
    nfts: number[],
    strategyAddress: string,
    strategyTreasuryAddress: string,
    options?: {
        limits?: BigNumberish[];
        strategyPerformanceTreasuryAddress?: string;
        tokenLimitPerAddress: BigNumberish;
        tokenLimit: BigNumberish;
        managementFee: BigNumberish;
        performanceFee: BigNumberish;
    }
): Promise<void> => {
    if (nfts.length === 0) {
        throw `Trying to combine 0 vaults`;
    }
    const { deployments, ethers } = hre;
    const { log } = deployments;
    const { deployer, admin } = await hre.getNamedAccounts();

    const TRANSACTION_GAS_LIMITS = {
        maxFeePerGas: ethers.BigNumber.from(90000000000),
        maxPriorityFeePerGas: ethers.BigNumber.from(40000000000),
    }
    const PRIVATE_VAULT = true;

    const firstNft = nfts[0];
    const firstAddress = await deployments.read(
        "VaultRegistry",
        "vaultForNft",
        firstNft
    );
    const vault = await hre.ethers.getContractAt("IVault", firstAddress);
    const tokens = await vault.vaultTokens();

    const {
        limits = tokens.map((_: any) => ethers.constants.MaxUint256),
        strategyPerformanceTreasuryAddress = strategyTreasuryAddress,
        tokenLimitPerAddress = ethers.constants.MaxUint256,
        tokenLimit = ethers.constants.MaxUint256,
        managementFee = 2 * 10 ** 7,
        performanceFee = 20 * 10 ** 7,
    } = options || {};

    await setupVault(hre, expectedNft, "ERC20RootVaultGovernance", {
        createVaultArgs: [tokens, strategyAddress, nfts, deployer],
        delayedStrategyParams: {
            strategyTreasury: strategyTreasuryAddress,
            strategyPerformanceTreasury: strategyPerformanceTreasuryAddress,
            managementFee: BigNumber.from(managementFee),
            performanceFee: BigNumber.from(performanceFee),
            privateVault: PRIVATE_VAULT,
            depositCallbackAddress: ethers.constants.AddressZero,
            withdrawCallbackAddress: ethers.constants.AddressZero,
        },
        strategyParams: {
            tokenLimitPerAddress: BigNumber.from(tokenLimitPerAddress),
            tokenLimit: BigNumber.from(tokenLimit),
        },
    });
    const rootVault = await deployments.read(
        "VaultRegistry",
        "vaultForNft",
        expectedNft
    );
    if (PRIVATE_VAULT) {
        const rootVaultContract = await hre.ethers.getContractAt(
            "ERC20RootVault",
            rootVault
        );
        const depositors = (await rootVaultContract.depositorsAllowlist()).map(
            (x: any) => x.toString()
        );
        if (!depositors.includes(admin)) {
            log("Adding admin to depositors");
            const tx =
                await rootVaultContract.populateTransaction.addDepositorsToAllowlist(
                    [admin]
                );
            const [operator] = await hre.ethers.getSigners();
            const txResp = await operator.sendTransaction(tx);
            log(
                `Sent transaction with hash \`${txResp.hash}\`. Waiting confirmation`
            );
            const receipt = await txResp.wait(1);
            log("Transaction confirmed");
        }
    }
    await deployments.execute(
        "VaultRegistry",
        { from: deployer, autoMine: true, ...TRANSACTION_GAS_LIMITS },
        "transferFrom(address,address,uint256)",
        deployer,
        rootVault,
        expectedNft
    );
};
