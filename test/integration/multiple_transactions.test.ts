import hre, { getNamedAccounts } from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    compareAddresses,
    encodeToBytes,
    generateSingleParams,
    mint,
    mintUniV3Position_USDC_WETH,
    now,
    randomAddress,
    randomChoice,
    sleep,
    sleepTo,
    uniSwapTokensGivenInput,
    uniSwapTokensGivenOutput,
    withSigner,
} from "../library/Helpers";
import { contract, TestContext } from "../library/setup";
import { pit, RUNS, uint256 } from "../library/property";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { YearnVault } from "../types/YearnVault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults, ALLOW_MASK } from "../../deploy/0000_utils";
import { expect, assert } from "chai";
import { abi as INonfungiblePositionManagerABI } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    AaveVault,
    AaveVault__factory,
    ERC20RootVaultGovernance,
    ERC20Token,
    IIntegrationVault,
    ILendingPool,
    INonfungiblePositionManager,
    IntegrationVault,
    IUniswapV3Pool,
    MellowOracle,
    TickMathTest,
    UniV3Vault,
    Vault,
} from "../types";
import { Address } from "hardhat-deploy/dist/types";
import { generateKeyPair, randomBytes, randomInt } from "crypto";
import { last, none, range } from "ramda";
import { runInThisContext } from "vm";
import { fromAscii } from "ethjs-util";
import { resourceLimits } from "worker_threads";
import { BigNumberish } from "ethers";
import { deployMathTickTest } from "../library/Deployments";
import { LiquidityMath, tickToPrice } from "@uniswap/v3-sdk";

type PullAction = {
    from: IIntegrationVault;
    to: IIntegrationVault;
    amount: BigNumber[];
};

type VaultStateChange = {
    amount: BigNumber[];
    timestamp: BigNumber;
    balanceBefore: BigNumber;
    balanceAfter: BigNumber;
};

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    uniV3Vault: UniV3Vault;
    erc20RootVaultNft: number;
    usdcDeployerSupply: BigNumber;
    wethDeployerSupply: BigNumber;
    strategyTreasury: Address;
    strategyPerformanceTreasury: Address;
    mellowOracle: MellowOracle;
    targets: IntegrationVault[];
    aTokens: ERC20Token[];
    uniV3Pool: IUniswapV3Pool;
    tickMath: TickMathTest;
    uniV3Fees: BigNumber[];
    positionManager: INonfungiblePositionManager;
}

type DeployOptions = {
    targets: IntegrationVault[];
};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__multiple_transactions",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

                    this.tokens = [this.usdc, this.weth];
                    for (let i = 1; i < this.tokens.length; i++) {
                        assert(
                            compareAddresses(
                                this.tokens[i - 1].address,
                                this.tokens[i].address
                            ) < 0
                        );
                    }
                    this.tokenAddresses = this.tokens.map((t) =>
                        t.address.toLowerCase()
                    );
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    this.uniV3PoolFee = 3000;

                    this.erc20VaultNft = startNft;
                    this.aaveVaultNft = startNft + 1;
                    this.uniV3VaultNft = startNft + 2;
                    this.yearnVaultNft = startNft + 3;
                    await setupVault(
                        hre,
                        this.erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [
                                this.tokenAddresses,
                                this.deployer.address,
                            ],
                        }
                    );
                    await setupVault(
                        hre,
                        this.aaveVaultNft,
                        "AaveVaultGovernance",
                        {
                            createVaultArgs: [
                                this.tokenAddresses,
                                this.deployer.address,
                            ],
                        }
                    );
                    await setupVault(
                        hre,
                        this.uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                this.tokenAddresses,
                                this.deployer.address,
                                this.uniV3PoolFee,
                            ],
                        }
                    );
                    await setupVault(
                        hre,
                        this.yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [
                                this.tokenAddresses,
                                this.deployer.address,
                            ],
                        }
                    );
                    await combineVaults(
                        hre,
                        this.yearnVaultNft + 1,
                        [
                            this.erc20VaultNft,
                            this.aaveVaultNft,
                            this.uniV3VaultNft,
                            this.yearnVaultNft,
                        ],
                        this.deployer.address,
                        this.deployer.address
                    );

                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.erc20VaultNft
                    );
                    const aaveVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.aaveVaultNft
                    );
                    const uniV3Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.uniV3VaultNft
                    );
                    const yearnVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.yearnVaultNft
                    );
                    const erc20RootVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.yearnVaultNft + 1
                    );

                    this.subject = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );
                    this.erc20Vault = (await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    )) as ERC20Vault;
                    this.aaveVault = (await ethers.getContractAt(
                        "AaveVault",
                        aaveVault
                    )) as AaveVault;
                    this.uniV3Vault = (await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault
                    )) as UniV3Vault;
                    this.yearnVault = (await ethers.getContractAt(
                        "YearnVault",
                        yearnVault
                    )) as YearnVault;

                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    this.wethDeployerSupply = BigNumber.from(10)
                        .pow(18)
                        .mul(300);
                    this.usdcDeployerSupply = BigNumber.from(10)
                        .pow(18)
                        .mul(300);

                    await mint(
                        "USDC",
                        this.deployer.address,
                        this.usdcDeployerSupply
                    );
                    await mint(
                        "WETH",
                        this.deployer.address,
                        this.wethDeployerSupply
                    );

                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );

                    this.strategyTreasury = randomAddress();
                    this.strategyPerformanceTreasury = randomAddress();

                    const {
                        uniswapV3PositionManager,
                        aaveLendingPool,
                        uniswapV3Factory,
                        uniswapV3Router,
                    } = await getNamedAccounts();
                    this.aaveLendingPool = (await ethers.getContractAt(
                        "ILendingPool",
                        aaveLendingPool
                    )) as ILendingPool;

                    this.aTokensAddresses = await Promise.all(
                        this.tokens.map(async (token) => {
                            return (
                                await this.aaveLendingPool.getReserveData(
                                    token.address
                                )
                            ).aTokenAddress;
                        })
                    );

                    this.aTokens = await Promise.all(
                        this.aTokensAddresses.map(
                            async (aTokenAddress: string) => {
                                return await ethers.getContractAt(
                                    "ERC20Token",
                                    aTokenAddress
                                );
                            }
                        )
                    );

                    this.yTokensAddresses = await Promise.all(
                        this.tokens.map(async (token) => {
                            return await this.yearnVaultGovernance.yTokenForToken(
                                token.address
                            );
                        })
                    );

                    this.yTokens = await Promise.all(
                        this.yTokensAddresses.map(
                            async (yTokenAddress: string) => {
                                return await ethers.getContractAt(
                                    "ERC20Token",
                                    yTokenAddress
                                );
                            }
                        )
                    );

                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManagerABI,
                        uniswapV3PositionManager
                    );

                    this.mapVaultsToNames = {};
                    this.mapVaultsToNames[this.erc20Vault.address] =
                        "zeroVault";
                    this.mapVaultsToNames[this.aaveVault.address] = "aaveVault";
                    this.mapVaultsToNames[this.yearnVault.address] =
                        "yearnVault";
                    this.mapVaultsToNames[this.uniV3Vault.address] =
                        "uniV3Vault";

                    this.erc20RootVaultNft = this.yearnVaultNft + 1;

                    this.uniswapV3Factory = await ethers.getContractAt(
                        "IUniswapV3Factory",
                        uniswapV3Factory
                    );

                    let poolAddress = await this.uniswapV3Factory.getPool(
                        this.tokens[0].address,
                        this.tokens[1].address,
                        this.uniV3PoolFee
                    );

                    this.uniV3Pool = await ethers.getContractAt(
                        "IUniswapV3Pool",
                        poolAddress
                    );
                    this.swapRouter = await ethers.getContractAt(
                        ISwapRouter,
                        uniswapV3Router
                    );
                    this.tickMath = await deployMathTickTest();

                    this.uniV3Fees = [BigNumber.from(0), BigNumber.from(0)];


                    this.optionsAave = encodeToBytes(
                        ["uint256"],
                        [ethers.constants.Zero]
                    );
                    this.optionsUniV3 = encodeToBytes(
                        ["uint256", "uint256", "uint256"],
                        [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                            ethers.constants.MaxUint256,
                        ]
                    );
                    this.optionsYearn = encodeToBytes(
                        ["uint256"],
                        [BigNumber.from(10000)]
                    );
                    return this.subject;
                }
            );
        });

        async function printPullAction(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            action: PullAction
        ) {
            process.stdout.write("Pulling ");
            process.stdout.write(
                action.amount[0].toString() + "," + action.amount[1].toString()
            );
            process.stdout.write(" from ");
            process.stdout.write(this.mapVaultsToNames[action.from.address]);
            process.stdout.write(" to ");
            process.stdout.write(this.mapVaultsToNames[action.to.address]);
            process.stdout.write("\n");
        }

        async function printLiquidityStats(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ) {
            if (!this.uniV3Nft.eq(0)) {
                let result = await this.positionManager.positions(this.uniV3Nft);
                console.log("liquidity");
                console.log(result["liquidity"].toString());
                console.log(result["tokensOwed0"].toString());
                console.log(result["tokensOwed1"].toString());
                return result;
            } else {
                console.log("nft is 0");
            }
        }

        async function printVaults(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ) {
            let allCurrenciesBalancePromises = this.targets.map(
                async (target) => {
                    let currentBalancesPromises = this.tokens.map((token) =>
                        token.balanceOf(target.address)
                    );
                    let currentBalancesResults = await Promise.all(
                        currentBalancesPromises
                    );
                    return currentBalancesResults;
                }
            );
            let allCurrenciesBalanceResult = await Promise.all(
                allCurrenciesBalancePromises
            );
            // console.log("Currencies balances:")
            // for (let i = 0; i < this.targets.length; i++) {
            //     process.stdout.write(allCurrenciesBalanceResult[i][0].toString() + " " + allCurrenciesBalanceResult[i][1].toString() + " | ");
            // }
            // process.stdout.write("\n");
            console.log("Tvls:");
            let tvlPromises = this.targets.map((target: Vault) => target.tvl());
            let tvlResults = await Promise.all(tvlPromises);
            this.targets.filter((target, index) =>
                process.stdout.write(tvlResults[index][0] + " | ")
            );
            process.stdout.write("\n");
            this.targets.filter((target, index) =>
                process.stdout.write(tvlResults[index][1] + " | ")
            );
            process.stdout.write("\n");

            return tvlResults;
        }

        async function randomPullAction(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ): Promise<PullAction | undefined> {
            let tvls = await Promise.all(
                this.targets.map((target) => target.tvl())
            );
            let nonEmptyVaults = this.targets.filter((target, index) => {
                return tvls[index][0][0].gt(0) || tvls[index][0][1].gt(0);
            });
            let { item: pullTarget } = randomChoice(nonEmptyVaults);
            let pullTargetIndex = this.targets.indexOf(pullTarget);
            let pullAmount = this.tokens.map((token, index) =>
                BigNumber.from(tvls[pullTargetIndex][1][index])
                    .mul(randomInt(1, 4))
                    .div(3)
            );
            let pushTarget = this.erc20Vault;
            if (pullTarget == this.erc20Vault) {
                let pushCandidates = this.targets.filter(
                    (target: Vault) => target != pullTarget
                );
                let poolSlot0 = await this.uniV3Pool.slot0();
                let largerCoinIndex = poolSlot0.tick >= 0 ? 0 : 1;
                let ratio = poolSlot0.tick
                    ? getRatioFromPriceX96(poolSlot0.sqrtPriceX96)
                    : getReverseRatioFromPriceX96(poolSlot0.sqrtPriceX96);
                if (
                    pullAmount[largerCoinIndex].lt(1) ||
                    pullAmount[1 - largerCoinIndex].lt(ratio)
                ) {
                    pushCandidates = pushCandidates.filter(
                        (target: Vault) => target != this.uniV3Vault
                    );
                }
                if (pushCandidates.length == 0) {
                    return undefined;
                }
                pushTarget = randomChoice(pushCandidates).item;
            }
            return { from: pullTarget, to: pushTarget, amount: pullAmount };
        }

        function randomBignumber(min: BigNumber, max: BigNumber) {
            assert(max.gt(min), "Bignumber underflow");
            const big = generateSingleParams(uint256);
            let sub = max.sub(min);
            return big.mod(sub).add(min);
        }

        async function doRandomEnvironmentChange(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ) {
            let target = randomChoice(this.targets).item;
            if (target == this.aaveVault) {
                sleep(randomInt(10000));
            } else if (
                target == this.uniV3Vault &&
                !this.uniV3Nft.eq(0)
            ) {
                let zeroForOne = randomChoice([true, false]).item;
                let liquidity = await this.uniV3Pool.liquidity();
                let tickLower = (await this.uniV3Pool.slot0()).tick;
                let priceBetweenTicks = (
                    await this.tickMath.getSqrtRatioAtTick(tickLower)
                )
                    .add(await this.tickMath.getSqrtRatioAtTick(tickLower + 1))
                    .div(2);
                let liquidityToAmount = zeroForOne
                    ? liquidityToX
                    : liquidityToY;
                let minRecieveFromSwapAmount = await liquidityToAmount.call(
                    this,
                    priceBetweenTicks,
                    tickLower + 1,
                    tickLower,
                    liquidity
                );
                let recieveFromSwapAmount = minRecieveFromSwapAmount.mul(
                    randomInt(1, 10)
                );
                let swapFees = await getFeesFromSwap.call(
                    this,
                    recieveFromSwapAmount,
                    zeroForOne
                );
                this.uniV3Fees[0] = this.uniV3Fees[0].add(swapFees[0]);
                this.uniV3Fees[1] = this.uniV3Fees[1].add(swapFees[1]);
                await uniSwapTokensGivenOutput(
                    this.swapRouter,
                    this.tokens,
                    this.uniV3PoolFee,
                    zeroForOne,
                    recieveFromSwapAmount
                );
            }
        }

        async function liquidityToY(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            sqrtPriceX96: BigNumber,
            tickUpper: number,
            tickLower: number,
            liquidity: BigNumber
        ) {
            let tickLowerPriceX96 = await this.tickMath.getSqrtRatioAtTick(
                tickLower
            );
            return sqrtPriceX96
                .sub(tickLowerPriceX96)
                .mul(liquidity)
                .div(BigNumber.from(2).pow(96));
        }

        async function liquidityToX(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            sqrtPriceX96: BigNumber,
            tickUpper: number,
            tickLower: number,
            liquidity: BigNumber
        ) {
            let tickUpperPriceX96 = await this.tickMath.getSqrtRatioAtTick(
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

        async function getFeesFromSwap(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            amount: BigNumber,
            zeroForOne: boolean
        ) {
            let currentTick = (await this.uniV3Pool.slot0()).tick;
            let currentPrice = (await this.uniV3Pool.slot0()).sqrtPriceX96;
            let currentLiquidity = await this.uniV3Pool.liquidity();
            let fees: BigNumber = BigNumber.from(0);
            let myLiquidity = (await this.positionManager.positions(this.uniV3Nft))
                .liquidity;
            while (amount.gt(0)) {
                // console.log("amount left: " + amount.toString());
                // console.log("current tick: " + currentTick);

                let amountToNextTick;
                if (zeroForOne) {
                    amountToNextTick = await liquidityToX.call(
                        this,
                        currentPrice,
                        currentTick + 1,
                        currentTick,
                        currentLiquidity
                    );
                } else {
                    amountToNextTick = await liquidityToY.call(
                        this,
                        currentPrice,
                        currentTick + 1,
                        currentTick,
                        currentLiquidity
                    );
                }
                let currentSwapAmount = amount.lt(amountToNextTick)
                    ? amount
                    : amountToNextTick;
                let currentSwapAmountInOtherCoin: BigNumber,
                    newPrice: BigNumber;
                if (zeroForOne) {
                    newPrice = sqrtPriceAfterXChange(
                        currentPrice,
                        currentSwapAmount,
                        currentLiquidity
                    );
                    currentSwapAmountInOtherCoin = yAmountUsedInSwap(
                        currentPrice,
                        newPrice,
                        currentLiquidity
                    );
                } else {
                    newPrice = sqrtPriceAfterYChange(
                        currentPrice,
                        currentSwapAmount,
                        currentLiquidity
                    );
                    currentSwapAmountInOtherCoin = xAmountUsedInSwap(
                        currentPrice,
                        newPrice,
                        currentLiquidity
                    );
                    // if (!amount.lt(amountToNextTick)) {
                    //     let tickSqrt = (await this.tickMath.getSqrtRatioAtTick(currentTick))
                    //     assert(tickSqrt.div(BigNumber.from(2).pow(96)).eq(newPrice.div(BigNumber.from(2).pow(96))), "prices differ: " + tickSqrt.div(BigNumber.from(2).pow(96)).toString() + " != " + newPrice.div(BigNumber.from(2).pow(96).toString()));
                    // }
                }
                // console.log("old price: " + currentPrice.toString());
                // console.log("new price: " + newPrice.toString());
                // console.log(
                //     "price in first token: " + currentSwapAmount.toString()
                // );
                // console.log(
                //     "price in other token: " +
                //         currentSwapAmountInOtherCoin.toString()
                // );
                // console.log("current amount: " + currentSwapAmount.toString());
                if (
                    this.tickUpper > currentTick &&
                    currentTick >= this.tickLower
                ) {
                    // console.log("+FEES");
                    // console.log("liquidities:");
                    // console.log(myLiquidity.toString());
                    // console.log(currentLiquidity.toString());
                    fees = fees.add(
                        currentSwapAmountInOtherCoin
                            .mul(myLiquidity)
                            .mul(this.uniV3PoolFee)
                            .div(currentLiquidity)
                            .div(1000000)
                    );
                }
                amount = amount.sub(currentSwapAmount);
                if (zeroForOne) {
                    currentPrice = await this.tickMath.getSqrtRatioAtTick(
                        currentTick + 1
                    );
                    currentTick += 1;
                    let tickInfo = await this.uniV3Pool.ticks(currentTick);
                    currentLiquidity = currentLiquidity.add(
                        tickInfo.liquidityNet
                    );
                } else {
                    currentPrice = await this.tickMath.getSqrtRatioAtTick(
                        currentTick
                    );
                    currentTick -= 1;
                    let tickInfo = await this.uniV3Pool.ticks(currentTick);
                    currentLiquidity = currentLiquidity.sub(
                        tickInfo.liquidityNet
                    );
                }
            }
            if (zeroForOne) {
                return [BigNumber.from(0), fees];
            } else {
                return [fees, BigNumber.from(0)];
            }
        }

        async function priceInTickRange(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            price: BigNumber,
            upperTick: number,
            lowerTick: number
        ) {
            let upperTickPrice = await this.tickMath.getSqrtRatioAtTick(upperTick);
            let lowerTickPrice = await this.tickMath.getSqrtRatioAtTick(lowerTick);
            price = price.gt(upperTickPrice) ? upperTickPrice : price;
            price = price.lt(lowerTickPrice) ? lowerTickPrice : price;
            return price;
        }

        async function countLiquidityChanges(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            liquidity: BigNumber,
            depositPrice: BigNumber,
            withdrawPrice: BigNumber,
            tickUpper: number,
            tickLower: number
        ) {
            depositPrice = await priceInTickRange.call(this, depositPrice, tickUpper, tickLower);
            withdrawPrice = await priceInTickRange.call(this, withdrawPrice, tickUpper, tickLower);
            let depositX = await liquidityToX.call(this, depositPrice, tickUpper, tickLower, liquidity);
            let depositY = await liquidityToY.call(this, depositPrice, tickUpper, tickLower, liquidity);
            let withdrawX = await liquidityToX.call(this, withdrawPrice, tickUpper, tickLower, liquidity);
            console.log("price were: " + depositPrice.toString() + ", price became: " + withdrawPrice.toString())
            let withdrawY = await liquidityToY.call(this, withdrawPrice, tickUpper, tickLower, liquidity);
            console.log("for L=" + liquidity.toString() + ", assets were: [" + depositX.toString() + ", " + depositY.toString() + "], they became: ["+ depositX.toString() + ", " + depositY.toString() + "]");
            return [withdrawX.sub(depositX), withdrawY.sub(depositY)];
        }

        function getRatioFromPriceX96(priceX96: BigNumber): BigNumber {
            return priceX96.pow(2).div(BigNumber.from(2).pow(192));
        }
        function getReverseRatioFromPriceX96(priceX96: BigNumber): BigNumber {
            return BigNumber.from(2).pow(192).div(priceX96.pow(2));
        }

        async function fullPullAction(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            pullTarget: IntegrationVault
        ): Promise<PullAction> {
            let tvls = await pullTarget.tvl();
            let pullAmount = this.tokens.map((token, index) =>
                BigNumber.from(tvls[1][index])
            );
            return {
                from: pullTarget,
                to: this.erc20Vault,
                amount: pullAmount,
            };
        }

        async function getLiquidityState(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            vaultAddress: string
        ) {
            if (
                vaultAddress == this.aaveVault.address ||
                vaultAddress == this.yearnVault.address
            ) {
                return Promise.all(
                    this.aTokens.map((aToken) => aToken.balanceOf(vaultAddress))
                );
            } else if (vaultAddress == this.uniV3Vault.address) {
                let price = (await this.uniV3Pool.slot0()).sqrtPriceX96;
                let realNft = await this.uniV3Vault.uniV3Nft();
                if (!realNft.eq(this.uniV3Nft)) {
                    console.log("NOT EQUAL " + realNft.toString() + " " + this.uniV3Nft.toString());
                }
                if (!this.uniV3Nft.eq(0)) {
                    let result = await this.positionManager.positions(this.uniV3Nft);
                    return [result.liquidity, price];
                } else {
                    return [BigNumber.from(0), price]
                }
            }
            return [BigNumber.from(0), BigNumber.from(0)];
        }

        async function doPullAction(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            action: PullAction
        ) {
            let options: any = [];
            if (action.to.address == this.aaveVault.address) {
                options = this.optionsAave;
            } else if (action.to.address == this.uniV3Vault.address) {
                options = this.optionsUniV3;
            }
            let fromLiquidityStateBefore = await getLiquidityState.call(
                this,
                action.from.address
            );
            let toLiquidityStateBefore = await getLiquidityState.call(
                this,
                action.to.address
            );
            let currentTimestamp = (await ethers.provider.getBlock("latest"))
                .timestamp;
            if (
                !(action.to.address == this.uniV3Vault.address &&
                this.uniV3VaultIsEmpty)
            ) {    
                await withSigner(this.subject.address, async (signer) => {
                    await action.from
                        .connect(signer)
                        .pull(
                            action.to.address,
                            this.tokenAddresses,
                            action.amount,
                            options
                        );
                });
            } else {
                console.log("REOPENING POSITION");
                let tickSpacing = await this.uniV3Pool.tickSpacing();
                let currentTick = (await this.uniV3Pool.slot0()).tick;
                let positionLength = randomInt(1, 4);
                let lowestTickAvailible =
                    currentTick - (currentTick % tickSpacing) - tickSpacing;
                let lowerTick =
                    lowestTickAvailible +
                    tickSpacing * 4;//randomInt(0, 4 - positionLength);
                let upperTick = lowerTick + tickSpacing * positionLength;
                // lowerTick = -887220;
                // upperTick = 887220;
                await pullToUniV3Vault.call(this, action.from, {
                    fee: this.uniV3PoolFee,
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    token0Amount: action.amount[0],
                    token1Amount: action.amount[1],
                });
                this.uniV3Nft = await this.uniV3Vault.uniV3Nft();
                this.uniV3VaultIsEmpty = false;    
            }
            let fromLiquidityStateAfter = await getLiquidityState.call(
                this,
                action.from.address
            );
            if (action.from.address == this.uniV3Vault.address) {
                await printVaults.call(this);
                console.log("liquidity left:" + fromLiquidityStateAfter[0].toString());
                await printLiquidityStats.call(this);
                if (fromLiquidityStateAfter[0].eq(0)) {
                    this.uniV3VaultIsEmpty = true;
                    await this.uniV3Vault.connect(this.deployer).collectEarnings();
                    // console.log("ITS EMPTY!");
                }
                await printVaults.call(this);
            }
            let toLiquidityStateAfter = await getLiquidityState.call(this, action.to.address);

            this.vaultChanges[action.from.address].push({
                amount: action.amount.map((amount) => amount.mul(-1)),
                timestamp: currentTimestamp,
                liquidityStateBefore: fromLiquidityStateBefore,
                liquidityStateAfter: fromLiquidityStateAfter,
                tickUpper: this.tickUpper,
                tickLower: this.tickLower 
            });
            this.vaultChanges[action.to.address].push({
                amount: action.amount,
                timestamp: currentTimestamp,
                liquidityStateBefore: toLiquidityStateBefore,
                liquidityStateAfter: toLiquidityStateAfter,
                tickUpper: this.tickUpper,
                tickLower: this.tickLower
            });
        }
        async function pullToUniV3Vault(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            sender: any,
            options: any
        ) {
            for (let token of this.tokens) {
                if (
                    (
                        await token.allowance(
                            sender.address,
                            this.positionManager.address
                        )
                    ).eq(BigNumber.from(0))
                ) {
                    await withSigner(sender.address, async (signer) => {
                        await token
                            .connect(signer)
                            .approve(
                                this.positionManager.address,
                                ethers.constants.MaxUint256
                            );
                    });
                }
            }

            const mintParams = {
                token0: this.tokens[0].address,
                token1: this.tokens[1].address,
                fee: options.fee,
                tickLower: options.tickLower,
                tickUpper: options.tickUpper,
                amount0Desired: options.token0Amount,
                amount1Desired: options.token1Amount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: sender.address,
                deadline: ethers.constants.MaxUint256,
            };
            this.tickLower = options.tickLower;
            this.tickUpper = options.tickUpper;

            await withSigner(sender.address, async (signer) => {
                const result = await this.positionManager
                    .connect(signer)
                    .callStatic.mint(mintParams);
                await this.positionManager.connect(signer).mint(mintParams);
                await withSigner(this.subject.address, async (root) => {
                    await this.vaultRegistry
                        .connect(root)
                        .approve(sender.address, this.uniV3VaultNft);
                });
                await this.positionManager
                    .connect(signer)
                    .functions["safeTransferFrom(address,address,uint256)"](
                        sender.address,
                        this.uniV3Vault.address,
                        result.tokenId
                    );
                if (!this.uniV3Nft.eq(0)) {
                    await this.positionManager.connect(signer).burn(this.uniV3Nft);
                }
            });
        }

        async function countChanges(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            vaultAddress: string
        ) {
            let stateChanges = this.vaultChanges[vaultAddress];
            let changes: BigNumber[] = [BigNumber.from(0), BigNumber.from(0)];
            if (
                vaultAddress == this.aaveVault.address ||
                vaultAddress == this.yearnVault.address
            ) {
                for (
                    let tokenIndex = 0;
                    tokenIndex < this.tokens.length;
                    tokenIndex++
                ) {
                    let tokenChanges = BigNumber.from(0);
                    for (let i = 1; i < stateChanges.length; i++) {
                        tokenChanges = tokenChanges
                            .add(stateChanges[i].balanceBefore[tokenIndex])
                            .sub(stateChanges[i - 1].balanceAfter[tokenIndex]);
                    }
                    changes.push(tokenChanges);
                }
            } else if (vaultAddress == this.uniV3Vault.address) {
                //TODO v plus ili v minus
                console.log("UniV3Fees are " + this.uniV3Fees[0].toString() + ", " + this.uniV3Fees[1].toString())
                let liquidityStates = [];
                for (let i = 0; i < stateChanges.length; i++) {
                    let liquidityBefore = stateChanges[i].liquidityStateBefore[0]
                    let liquidityAfter = stateChanges[i].liquidityStateAfter[0]
                    if (!liquidityBefore.eq(liquidityAfter)) {
                        let currentPrice = stateChanges[i].liquidityStateAfter[1];
                        if (liquidityAfter.gt(liquidityBefore)) {
                            liquidityStates.push({liquidity: liquidityAfter.sub(liquidityBefore), price: currentPrice});
                        } else {
                            let liquidityWithdrawn = liquidityBefore.sub(liquidityAfter);
                            while (liquidityWithdrawn.gt(0)) {
                                let lastLiquidityDeposit = liquidityStates[liquidityStates.length - 1];
                                let liquidityToChange = liquidityWithdrawn.gt(lastLiquidityDeposit.liquidity) ? lastLiquidityDeposit.liquidity : liquidityWithdrawn;
                                let liquidityChanges = await countLiquidityChanges.call(this, liquidityToChange, lastLiquidityDeposit.price, currentPrice, stateChanges[i].tickUpper, stateChanges[i].tickLower);
                                liquidityWithdrawn = liquidityWithdrawn.sub(liquidityToChange);
                                changes[0] = changes[0].add(liquidityChanges[0]);
                                changes[1] = changes[1].add(liquidityChanges[1]);
                            }
                        }
                    }
                }
                changes[0] = changes[0].sub(this.uniV3Fees[0]);
                changes[1] = changes[1].sub(this.uniV3Fees[1]);
            }
            return changes;
        }

        before(async () => {
            this.setZeroFeesFixture = deployments.createFixture(async (_, options?: DeployOptions) => {
                this.targets = options ? options.targets : [this.erc20Vault, this.aaveVault, this.uniV3Vault, this.yearnVault];
                let erc20RootVaultGovernance: ERC20RootVaultGovernance =
                    await ethers.getContract("ERC20RootVaultGovernance");

                await erc20RootVaultGovernance
                    .connect(this.admin)
                    .stageDelayedStrategyParams(this.erc20RootVaultNft, {
                        strategyTreasury: this.strategyTreasury,
                        strategyPerformanceTreasury:
                            this.strategyPerformanceTreasury,
                        privateVault: true,
                        managementFee: 0,
                        performanceFee: 0,
                        depositCallbackAddress: ethers.constants.AddressZero,
                        withdrawCallbackAddress: ethers.constants.AddressZero,
                    });
                await sleep(this.governanceDelay);
                await this.erc20RootVaultGovernance
                    .connect(this.admin)
                    .commitDelayedStrategyParams(this.erc20RootVaultNft);

                const { protocolTreasury } = await getNamedAccounts();

                const params = {
                    forceAllowMask: ALLOW_MASK,
                    maxTokensPerVault: 10,
                    governanceDelay: 86400,
                    protocolTreasury,
                    withdrawLimit: BigNumber.from(10).pow(20),
                };
                await this.protocolGovernance
                    .connect(this.admin)
                    .stageParams(params);
                await sleep(this.governanceDelay);
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitParams();
                this.vaultChanges = {};
                for (let x of this.targets) {
                    this.vaultChanges[x.address] = [];
                }
                this.uniV3Nft = BigNumber.from(0);
                this.uniV3VaultIsEmpty = true;
            });
        });

        beforeEach(async() => {
            await this.deploymentFixture();
        })
        describe("properties", () => {
            it("zero fees", async () => {
                let targets = [this.erc20Vault, this.uniV3Vault];
                await this.setZeroFeesFixture({targets:targets});
                
                //DEPOSIT
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(10),
                    BigNumber.from(10).pow(18).mul(10),
                ];
                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);

                //RANDOM ACTIONS
                for (let i = 0; i < 100; i++) {
                    await printVaults.call(this);
                    if (randomInt(2) == 0) {
                        await doRandomEnvironmentChange.call(this);
                    } else {
                        let randomAction = await randomPullAction.call(this);
                        if (randomAction == undefined) {
                            continue;
                        }
                        await printPullAction.call(this, randomAction);
                        await doPullAction.call(this, randomAction);
                    }
                }

                //PULL EVERYTHING TO ZERO
                for (let i = 1; i < this.targets.length; i++) {
                    let pullAction = await fullPullAction.call(
                        this,
                        this.targets[i]
                    );
                    await printPullAction.call(this, pullAction);
                    await doPullAction.call(this, pullAction);
                }
                await this.uniV3Vault.connect(this.deployer).collectEarnings();

                await printVaults.call(this);

                //WITHDRAW
                let lpAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                let actualWithdraw = await this.subject
                    .connect(this.deployer)
                    .callStatic.withdraw(
                        this.deployer.address,
                        lpAmount,
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                await this.subject
                    .connect(this.deployer)
                    .withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                console.log(
                    "Withdrawn: " +
                        actualWithdraw[0].toString() +
                        " " +
                        actualWithdraw[1].toString()
                );

                //COUNT CHANGES IN EVERY VAULT
                let targetChanges = [];
                for (let target of this.targets) {
                    let profit = await countChanges.call(this, target.address);
                    targetChanges.push(profit);
                    console.log(
                        this.mapVaultsToNames[target.address] +
                            " changes are " +
                            profit[0].toString() +
                            ", " +
                            profit[1].toString()
                    );
                }

                //EXPECT DEBIT EQUALS CREDIT
                for (
                    let tokenIndex = 0;
                    tokenIndex < this.tokens.length;
                    tokenIndex++
                ) {
                    let expectedWithdraw = depositAmount[tokenIndex];
                    for (let changes of targetChanges) {
                        expectedWithdraw = expectedWithdraw.add(
                            changes[tokenIndex]
                        );
                    }
                    expect(expectedWithdraw).to.be.gt(
                        actualWithdraw[tokenIndex].mul(99).div(100)
                    );
                    expect(expectedWithdraw).to.be.lt(
                        actualWithdraw[tokenIndex].mul(101).div(100)
                    );
                }
            });

            it("testing aave", async () => {
                await this.setZeroFeesFixture({targets: [this.erc20Vault, this.aaveVault]});
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(10),
                    BigNumber.from(10).pow(18).mul(10),
                ];

                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);
                await printVaults.call(this);

                await withSigner(this.subject.address, async (signer) => {
                    let options = encodeToBytes(
                        ["uint256"],
                        [ethers.constants.Zero]
                    );
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.aaveVault.address,
                            this.tokenAddresses,
                            depositAmount,
                            options
                        );
                });

                await printVaults.call(this);

                console.log("sleeping");
                await sleep(1);

                let tvlResults = await printVaults.call(this);

                process.stdout.write("balance of aToken:");
                await Promise.all(
                    this.aTokens.map(async (aToken: any) => {
                        console.log("aToken " + aToken.address);
                        process.stdout.write(
                            (
                                await aToken.balanceOf(this.aaveVault.address)
                            ).toString() + " "
                        );
                    })
                );
                process.stdout.write("\n");

                await withSigner(this.subject.address, async (signer) => {
                    await this.aaveVault
                        .connect(signer)
                        .pull(
                            this.erc20Vault.address,
                            this.tokenAddresses,
                            tvlResults[1][1],
                            []
                        );
                });

                await printVaults.call(this);

                let tvls = await this.subject.tvl();
                console.log(
                    "MIN TVLS: " +
                        tvls[0][0].toString() +
                        " " +
                        tvls[0][1].toString()
                );
                console.log(
                    "MAX TVLS: " +
                        tvls[1][0].toString() +
                        " " +
                        tvls[1][1].toString()
                );

                let lpAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                let actualWithdraw = await this.subject
                    .connect(this.deployer)
                    .callStatic.withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                await this.subject
                    .connect(this.deployer)
                    .withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                console.log(
                    "Withdrawn: " +
                        actualWithdraw[0].toString() +
                        " " +
                        actualWithdraw[1].toString()
                );

                await printVaults.call(this);

                console.log(
                    "Balance is " +
                        ((await this.subject.balanceOf(this.deployer.address)) +
                            " MLP")
                );
            });

            it("testing yearn", async () => {
                await this.setZeroFeesFixture({targets :[this.erc20Vault, this.yearnVault]});
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(10),
                    BigNumber.from(10).pow(18).mul(10),
                ];

                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);
                await printVaults.call(this);

                await withSigner(this.subject.address, async (signer) => {
                    let options: any[] = [];
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.yearnVault.address,
                            this.tokenAddresses,
                            depositAmount,
                            options
                        );
                });

                await printVaults.call(this);

                console.log("sleeping");
                await sleep(1000000000);

                let tvlResults = await printVaults.call(this);

                process.stdout.write("balance of yToken:");
                await Promise.all(
                    this.yTokens.map(async (yToken: any) => {
                        console.log("yToken " + yToken.address);
                        process.stdout.write(
                            (
                                await yToken.balanceOf(this.yearnVault.address)
                            ).toString() + " "
                        );
                    })
                );
                process.stdout.write("\n");

                await withSigner(this.subject.address, async (signer) => {
                    await this.yearnVault
                        .connect(signer)
                        .pull(
                            this.erc20Vault.address,
                            this.tokenAddresses,
                            tvlResults[1][1],
                            []
                        );
                });

                await printVaults.call(this);

                let tvls = await this.subject.tvl();
                console.log(
                    "MIN TVLS: " +
                        tvls[0][0].toString() +
                        " " +
                        tvls[0][1].toString()
                );
                console.log(
                    "MAX TVLS: " +
                        tvls[1][0].toString() +
                        " " +
                        tvls[1][1].toString()
                );

                let lpAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                let actualWithdraw = await this.subject
                    .connect(this.deployer)
                    .callStatic.withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                await this.subject
                    .connect(this.deployer)
                    .withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                console.log(
                    "Withdrawn: " +
                        actualWithdraw[0].toString() +
                        " " +
                        actualWithdraw[1].toString()
                );

                await printVaults.call(this);

                console.log(
                    "Balance is " +
                        ((await this.subject.balanceOf(this.deployer.address)) +
                            " MLP")
                );
            });

            it("testing gross and net and tickspacing", async () => {
                for (let tickNumber = 0; tickNumber <= 60; tickNumber++) {
                    let tickData = await this.uniV3Pool.ticks(tickNumber);
                    console.log(
                        "tick " +
                            tickNumber +
                            ", gross is " +
                            tickData.liquidityGross +
                            ", net is " +
                            tickData.liquidityNet
                    );
                }
            });

            it("testing tick edges", async () => {
                let currentTick = (await this.uniV3Pool.slot0()).tick;
                let currentPrice = (await this.uniV3Pool.slot0()).sqrtPriceX96;
                let currentLiquidity = await this.uniV3Pool.liquidity();
                let upperBound = await this.tickMath.getSqrtRatioAtTick(
                    currentTick + 1
                );
                let lowerBound = await this.tickMath.getSqrtRatioAtTick(
                    currentTick
                );
                let upperBoundRatio = getRatioFromPriceX96(upperBound);
                let lowerBoundRatio = getRatioFromPriceX96(lowerBound);
                let currentRatio = getRatioFromPriceX96(currentPrice);
                console.log("current tick: " + currentTick);
                console.log("upper ratio: " + upperBoundRatio.toString());
                console.log("current ratio: " + currentRatio.toString());
                console.log("lower ratio: " + lowerBoundRatio.toString());
                console.log(
                    "currentLiquidity: " + currentLiquidity.toString()
                );
                let yLiquidity = currentPrice
                    .sub(lowerBound)
                    .mul(currentLiquidity)
                    .div(BigNumber.from(2).pow(96));
                console.log("yLiquidity");
                console.log(yLiquidity.toString());

                console.log("current tick: " + currentTick);
                console.log("taking from pool all liquidity except 10^12");
                await uniSwapTokensGivenOutput(
                    this.swapRouter,
                    this.tokens,
                    this.uniV3PoolFee,
                    false,
                    yLiquidity.sub(BigNumber.from(10).pow(12))
                );
                console.log(
                    "current tick: " + (await this.uniV3Pool.slot0()).tick
                );
                console.log("doing swap of 2 * 10^12 token");
                await uniSwapTokensGivenOutput(
                    this.swapRouter,
                    this.tokens,
                    this.uniV3PoolFee,
                    false,
                    BigNumber.from(10).pow(12).add(1)
                );
                console.log(
                    "current tick: " + (await this.uniV3Pool.slot0()).tick
                );
            });

            it("testing pool maths", async () => {
                let slot0 = await this.uniV3Pool.slot0();
                console.log(
                    "spacing is " + (await this.uniV3Pool.tickSpacing())
                );
                for (let i = 0; i < 15; i++) {
                    slot0 = await this.uniV3Pool.slot0();
                    console.log("tick is " + slot0.tick);
                    console.log(
                        "price is " +
                            getRatioFromPriceX96(slot0.sqrtPriceX96).toString()
                    );
                    await uniSwapTokensGivenInput(
                        this.swapRouter,
                        this.tokens,
                        this.uniV3PoolFee,
                        false,
                        BigNumber.from(10).pow(13).mul(2)
                    );
                }
            });
            it("testing univ3 edge cases", async () => {
                await this.setZeroFeesFixture({targets :[this.erc20Vault, this.uniV3Vault]});
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(3000).mul(200),
                    BigNumber.from(10).pow(18).mul(200),
                ];
                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);

                await printVaults.call(this);

                let slot0 = await this.uniV3Pool.slot0();
                console.log(
                    "price is " +
                        getRatioFromPriceX96(slot0.sqrtPriceX96).toString()
                );

                await pullToUniV3Vault.call(this, this.erc20Vault, {
                    fee: this.uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 196020,
                    token0Amount: BigNumber.from(10).pow(6).mul(3000).mul(50),
                    token1Amount: BigNumber.from(10).pow(18).mul(50),
                });

                let tvlResults = await printVaults.call(this);

                await withSigner(this.subject.address, async (signer) => {
                    console.log("gona push 1");
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.uniV3Vault.address,
                            this.tokenAddresses,
                            [0, 1000000],
                            this.optionsUniV3
                        );

                    let tvlResults = await printVaults.call(this);
                    console.log("return to zero");
                    await this.uniV3Vault
                        .connect(signer)
                        .pull(
                            this.erc20Vault.address,
                            this.tokenAddresses,
                            tvlResults[1][1],
                            []
                        );
                });

                await printVaults.call(this);

                let tvls = await this.subject.tvl();
                console.log(
                    "MIN TVLS: " +
                        tvls[0][0].toString() +
                        " " +
                        tvls[0][1].toString()
                );
                console.log(
                    "MAX TVLS: " +
                        tvls[1][0].toString() +
                        " " +
                        tvls[1][1].toString()
                );

                let lpAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                let actualWithdraw = await this.subject
                    .connect(this.deployer)
                    .callStatic.withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                await this.subject
                    .connect(this.deployer)
                    .withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                //unnecessarycheck
                console.log(
                    "Withdrawn: " +
                        actualWithdraw[0].toString() +
                        " " +
                        actualWithdraw[1].toString()
                );
                await printVaults.call(this);
                console.log(
                    "Balance is " +
                        ((await this.subject.balanceOf(this.deployer.address)) +
                            " MLP")
                );
            });
            it.only("testing univ3 edge cases 2", async () => {
                await this.setZeroFeesFixture({targets :[this.erc20Vault, this.uniV3Vault]});
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(3000).mul(200),
                    BigNumber.from(10).pow(18).mul(200),
                ];
                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);

                await printVaults.call(this);

                let slot0 = await this.uniV3Pool.slot0();
                console.log(
                    "price is " +
                        getRatioFromPriceX96(slot0.sqrtPriceX96).toString()
                );

                await pullToUniV3Vault.call(this, this.erc20Vault, {
                    fee: this.uniV3PoolFee,
                    tickLower: 196080,
                    tickUpper: 887220,
                    token0Amount: BigNumber.from(10).pow(6).mul(3000).mul(50),
                    token1Amount: BigNumber.from(10).pow(18).mul(50),
                });
                
                this.uniV3Nft = await this.uniV3Vault.uniV3Nft();
                let tvlResults = await printVaults.call(this);
                await printLiquidityStats.call(this);

                await withSigner(this.subject.address, async (signer) => {
                    console.log("gona push 1");
                    await this.uniV3Vault
                        .connect(signer)
                        .pull(
                            this.erc20Vault.address,
                            this.tokenAddresses,
                            [BigNumber.from("149999999999"), 0],
                            []
                        );

                    this.uniV3Nft = await this.uniV3Vault.uniV3Nft();
                    let tvlResults = await printVaults.call(this);
                    await printLiquidityStats.call(this);
                });

                await printVaults.call(this);

                let tvls = await this.subject.tvl();
                console.log(
                    "MIN TVLS: " +
                        tvls[0][0].toString() +
                        " " +
                        tvls[0][1].toString()
                );
                console.log(
                    "MAX TVLS: " +
                        tvls[1][0].toString() +
                        " " +
                        tvls[1][1].toString()
                );

                let lpAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                let actualWithdraw = await this.subject
                    .connect(this.deployer)
                    .callStatic.withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                await this.subject
                    .connect(this.deployer)
                    .withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                //unnecessarycheck
                console.log(
                    "Withdrawn: " +
                        actualWithdraw[0].toString() +
                        " " +
                        actualWithdraw[1].toString()
                );
                await printVaults.call(this);
                console.log(
                    "Balance is " +
                        ((await this.subject.balanceOf(this.deployer.address)) +
                            " MLP")
                );
            });

            it("testing univ3", async () => {

                await this.setZeroFeesFixture({targets :[this.erc20Vault, this.uniV3Vault]});
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(3000).mul(200),
                    BigNumber.from(10).pow(18).mul(200),
                ];
                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);

                await printVaults.call(this);

                await pullToUniV3Vault.call(this, this.erc20Vault, {
                    fee: this.uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    token0Amount: BigNumber.from(10).pow(6).mul(3000).mul(50),
                    token1Amount: BigNumber.from(10).pow(18).mul(50),
                });
                let slot0 = await this.uniV3Pool.slot0();
                console.log(
                    "price is " +
                        getRatioFromPriceX96(slot0.sqrtPriceX96).toString()
                );

                let tvlResults = await printVaults.call(this);
                console.log("several big swaps");
                let fees = [BigNumber.from(0), BigNumber.from(0)];
                let lastliq = BigNumber.from(0);
                for (let i = 0; i < 2; i++) {
                    let curliq = await this.uniV3Pool.liquidity();
                    if (!curliq.eq(lastliq)) {
                        console.log("liquidity changed:");
                        console.log(lastliq.sub(curliq).toString());
                    }
                    lastliq = curliq;
                    console.log("current tick:");
                    console.log((await this.uniV3Pool.slot0()).tick);
                    console.log("current price:");
                    console.log((await this.uniV3Pool.slot0()).sqrtPriceX96.toString());
                    let swapAmount = BigNumber.from(10).pow(3).mul(50);
                    // let swapFees = await getFeesFromSwap.call(
                    //     this,
                    //     recieveAmount,
                    //     true
                    // );
                    // fees[0] = fees[0].add(swapFees[0]);
                    // fees[1] = fees[1].add(swapFees[1]);
                    let amountOut = await uniSwapTokensGivenInput(
                        this.swapRouter,
                        this.tokens,
                        this.uniV3PoolFee,
                        false,
                        swapAmount
                    );
                }
                console.log("current tick:");
                console.log((await this.uniV3Pool.slot0()).tick);
                console.log("current price:");
                console.log((await this.uniV3Pool.slot0()).sqrtPriceX96);

                await withSigner(this.subject.address, async (signer) => {
                    let tvlPreFees = await printVaults.call(this);

                    console.log("collect fees");
                    await this.uniV3Vault.connect(signer).collectEarnings();

                    let tvlPostFees = await printVaults.call(this);

                    console.log("fees earned");
                    let feesEarned = [
                        tvlPostFees[0][0][0].sub(tvlPreFees[0][0][0]),
                        tvlPostFees[0][0][1].sub(tvlPreFees[0][0][1]),
                    ];
                    console.log(
                        feesEarned[0].toString() +
                            " " +
                            feesEarned[1].toString()
                    );
                    console.log(fees.toString());

                    console.log("stats are:");
                    await printLiquidityStats.call(this);

                    console.log("return to zero");
                    await this.uniV3Vault
                        .connect(signer)
                        .pull(
                            this.erc20Vault.address,
                            this.tokenAddresses,
                            tvlResults[1][1],
                            []
                        );
                });

                await printVaults.call(this);

                let tvls = await this.subject.tvl();
                console.log(
                    "MIN TVLS: " +
                        tvls[0][0].toString() +
                        " " +
                        tvls[0][1].toString()
                );
                console.log(
                    "MAX TVLS: " +
                        tvls[1][0].toString() +
                        " " +
                        tvls[1][1].toString()
                );

                let lpAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                let actualWithdraw = await this.subject
                    .connect(this.deployer)
                    .callStatic.withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                await this.subject
                    .connect(this.deployer)
                    .withdraw(
                        this.deployer.address,
                        lpAmount.mul(2),
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
                //unnecessarycheck
                console.log(
                    "Withdrawn: " +
                        actualWithdraw[0].toString() +
                        " " +
                        actualWithdraw[1].toString()
                );
                await printVaults.call(this);
                console.log(
                    "Balance is " +
                        ((await this.subject.balanceOf(this.deployer.address)) +
                            " MLP")
                );
            });
        });
    }
);
