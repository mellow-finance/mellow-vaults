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
import { integer } from "fast-check";
import { LiquidityMath, tickToPrice } from "@uniswap/v3-sdk";

type PullAction = {
    from: IIntegrationVault;
    to: IIntegrationVault;
    amount: BigNumber[];
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
    uniV3Nft: BigNumber;
    expectedUniV3Changes: BigNumber[];
};

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
                    this.tokensAddresses = this.tokens.map((t) =>
                        t.address.toLowerCase()
                    );
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    this.uniV3PoolFee = 3000;
                    this.uniV3PoolFeeDenominator = 1000000;

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
                                this.tokensAddresses,
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
                                this.tokensAddresses,
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
                                this.tokensAddresses,
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
                                this.tokensAddresses,
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
                    this.expectedUniV3Changes = [
                        BigNumber.from(0),
                        BigNumber.from(0),
                    ];
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
                let result = await this.positionManager.positions(
                    this.uniV3Nft
                );
                console.log("liquidity");
                console.log(result["liquidity"].toString());
                console.log(result.tokensOwed0.toString());
                console.log(result.tokensOwed1.toString());
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
            let random = randomInt(1, 4);
            console.log("Random is " + random);
            let pullAmount = this.tokens.map((token, index) => {
                if (pullTarget.address == this.uniV3Vault.address) {
                    return BigNumber.from(tvls[pullTargetIndex][1][index])
                        .mul(random)
                        .div(3);
                } else {
                    return BigNumber.from(tvls[pullTargetIndex][1][index])
                        .mul(randomInt(1, 4))
                        .div(3);
                }
            });
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
            } else if (pullTarget == this.uniV3Vault) {
                if (
                    tvls[pullTargetIndex][1][0].eq(pullAmount[0]) &&
                    tvls[pullTargetIndex][1][1].eq(pullAmount[1])
                ) {
                    pullAmount = pullAmount.map((amount) =>
                        amount.mul(6).div(5)
                    );
                }
            }
            return { from: pullTarget, to: pushTarget, amount: pullAmount };
        }

        async function doRandomEnvironmentChange(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ) {
            let target = randomChoice(this.targets).item;
            if (target == this.aaveVault) {
                sleep(randomInt(10000));
            } else if (target == this.uniV3Vault && !this.uniV3Nft.eq(0)) {
                let zeroForOne = randomChoice([true, false]).item;
                let liquidity = await this.uniV3Pool.liquidity();
                const { tick: tickLower, sqrtPriceX96: oldPrice } =
                    await this.uniV3Pool.slot0();
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
                let amountIn = await uniSwapTokensGivenOutput(
                    this.swapRouter,
                    this.tokens,
                    this.uniV3PoolFee,
                    zeroForOne,
                    recieveFromSwapAmount
                );

                let newPrice = (await this.uniV3Pool.slot0()).sqrtPriceX96;
                if (newPrice.gt(oldPrice)) {
                    console.log("Price went up");
                } else {
                    console.log("Price went down");
                }
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
            let myLiquidity = (
                await this.positionManager.positions(this.uniV3Nft)
            ).liquidity;
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
                            .div(this.uniV3PoolFeeDenominator)
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
            let upperTickPrice = await this.tickMath.getSqrtRatioAtTick(
                upperTick
            );
            let lowerTickPrice = await this.tickMath.getSqrtRatioAtTick(
                lowerTick
            );
            price = price.gt(upperTickPrice) ? upperTickPrice : price;
            price = price.lt(lowerTickPrice) ? lowerTickPrice : price;
            return price;
        }

        async function countLiquidityChanges(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            liquidity: BigNumber,
            depositPrice: BigNumber,
            withdrawPrice: BigNumber
        ) {
            depositPrice = await priceInTickRange.call(
                this,
                depositPrice,
                this.tickUpper,
                this.tickLower
            );
            withdrawPrice = await priceInTickRange.call(
                this,
                withdrawPrice,
                this.tickUpper,
                this.tickLower
            );

            if (!depositPrice.eq(withdrawPrice)) {
                let depositX = await liquidityToX.call(
                    this,
                    depositPrice,
                    this.tickUpper,
                    this.tickLower,
                    liquidity
                );
                let depositY = await liquidityToY.call(
                    this,
                    depositPrice,
                    this.tickUpper,
                    this.tickLower,
                    liquidity
                );
                let withdrawX = await liquidityToX.call(
                    this,
                    withdrawPrice,
                    this.tickUpper,
                    this.tickLower,
                    liquidity
                );
                console.log(
                    "price were: " +
                        depositPrice.toString() +
                        ", price became: " +
                        withdrawPrice.toString()
                );
                let withdrawY = await liquidityToY.call(
                    this,
                    withdrawPrice,
                    this.tickUpper,
                    this.tickLower,
                    liquidity
                );
                console.log(
                    "for L=" +
                        liquidity.toString() +
                        ", assets were: [" +
                        depositX.toString() +
                        ", " +
                        depositY.toString() +
                        "], they became: [" +
                        withdrawX.toString() +
                        ", " +
                        withdrawY.toString() +
                        "]"
                );
                return [withdrawX.sub(depositX), withdrawY.sub(depositY)];
            }
            return [BigNumber.from(0), BigNumber.from(0)];
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
                    console.log(
                        "NOT EQUAL " +
                            realNft.toString() +
                            " " +
                            this.uniV3Nft.toString()
                    );
                }
                if (!this.uniV3Nft.eq(0)) {
                    let result = await this.positionManager.positions(
                        this.uniV3Nft
                    );
                    return [result.liquidity, price];
                } else {
                    return [BigNumber.from(0), price];
                }
            }
            return [BigNumber.from(0), BigNumber.from(0)];
        }

        async function doPullAction(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            action: PullAction,
            last: boolean
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
                !(
                    action.to.address == this.uniV3Vault.address &&
                    this.uniV3VaultIsEmpty
                )
            ) {
                await withSigner(this.subject.address, async (signer) => {
                    await action.from
                        .connect(signer)
                        .pull(
                            action.to.address,
                            this.tokensAddresses,
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
                    tickSpacing * randomInt(0, 4 - positionLength);
                let upperTick = lowerTick + tickSpacing * positionLength;
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
            if (!this.uniV3Nft.eq(0)) {
                await this.uniV3Vault.connect(this.deployer).collectEarnings();
            }
            let fromLiquidityStateAfter = await getLiquidityState.call(
                this,
                action.from.address
            );
            if (action.from.address == this.uniV3Vault.address) {
                await printVaults.call(this);
                console.log(
                    "liquidity left:" + fromLiquidityStateAfter[0].toString()
                );
                await printLiquidityStats.call(this);
                await printVaults.call(this);
            }
            let toLiquidityStateAfter = await getLiquidityState.call(
                this,
                action.to.address
            );

            this.vaultChanges[action.from.address].push({
                amount: action.amount.map((amount) => amount.mul(-1)),
                timestamp: currentTimestamp,
                liquidityStateBefore: fromLiquidityStateBefore,
                liquidityStateAfter: fromLiquidityStateAfter,
            });
            this.vaultChanges[action.to.address].push({
                amount: action.amount,
                timestamp: currentTimestamp,
                liquidityStateBefore: toLiquidityStateBefore,
                liquidityStateAfter: toLiquidityStateAfter,
            });
            if (action.from.address == this.uniV3Vault.address) {
                if (fromLiquidityStateAfter[0].eq(0) || last) {
                    this.uniV3VaultIsEmpty = true;
                    let changes = await countUniV3Changes.call(this, false);
                    console.log(
                        "expected changes: " +
                            this.expectedUniV3Changes[0]
                                .add(this.uniV3Fees[0])
                                .toString() +
                            ", " +
                            this.expectedUniV3Changes[1]
                                .add(this.uniV3Fees[1])
                                .toString()
                    );
                    await printVaults.call(this);
                }
            }
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
                    await this.positionManager
                        .connect(signer)
                        .burn(this.uniV3Nft);
                }
            });
            this.uniV3Nft = await this.uniV3Vault.uniV3Nft();
        }

        async function countFees(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            vaultAddress: string
        ) {
            let stateChanges = this.vaultChanges[vaultAddress];
            let fees: BigNumber[] = [BigNumber.from(0), BigNumber.from(0)];
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
                            .add(
                                stateChanges[i].liquidityStateBefore[tokenIndex]
                            )
                            .sub(
                                stateChanges[i - 1].liquidityStateAfter[
                                    tokenIndex
                                ]
                            );
                    }
                    fees.push(tokenChanges);
                }
            } else if (vaultAddress == this.uniV3Vault.address) {
                console.log(
                    "UniV3Fees are " +
                        this.uniV3Fees[0].toString() +
                        ", " +
                        this.uniV3Fees[1].toString()
                );
                fees = this.uniV3Fees;
            }
            return fees;
        }

        async function countUniV3Changes(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            last:boolean
        ) {
            let liquidityStates: any[] = [];
            let stateChanges = this.vaultChanges[this.uniV3Vault.address];
            console.log("State Changes:");
            let changes = [BigNumber.from(0), BigNumber.from(0)];
            for (let i = 0; i < stateChanges.length; i++) {
                console.log("number " + i);
                let liquidityBefore = stateChanges[i].liquidityStateBefore[0];
                let liquidityAfter = stateChanges[i].liquidityStateAfter[0];
                console.log("liquidity before " + liquidityBefore.toString());
                console.log("liquidity after " + liquidityAfter.toString());
                console.log(
                    "price " + stateChanges[i].liquidityStateAfter[1].toString()
                );
                if (!liquidityBefore.eq(liquidityAfter)) {
                    let currentChanges = [BigNumber.from(0), BigNumber.from(0)];
                    let currentPrice = stateChanges[i].liquidityStateAfter[1];
                    if (liquidityAfter.gt(liquidityBefore)) {
                        liquidityStates.push({
                            liquidity: liquidityAfter.sub(liquidityBefore),
                            price: currentPrice,
                        });
                    } else {
                        let liquidityWithdrawn =
                            liquidityBefore.sub(liquidityAfter);
                        while (
                            liquidityWithdrawn.gt(0) &&
                            liquidityStates.length != 0
                        ) {
                            let lastLiquidityDeposit = liquidityStates.pop();
                            let liquidityToChange = liquidityWithdrawn.gt(
                                lastLiquidityDeposit.liquidity
                            )
                                ? lastLiquidityDeposit.liquidity
                                : liquidityWithdrawn;
                            if (!lastLiquidityDeposit.price.eq(currentPrice)) {
                                let liquidityChanges =
                                    await countLiquidityChanges.call(
                                        this,
                                        liquidityToChange,
                                        lastLiquidityDeposit.price,
                                        currentPrice
                                    );
                                currentChanges[0] = currentChanges[0].add(
                                    liquidityChanges[0]
                                );
                                currentChanges[1] = currentChanges[1].add(
                                    liquidityChanges[1]
                                );
                            }
                            if (
                                lastLiquidityDeposit.liquidity.gt(
                                    liquidityWithdrawn
                                )
                            ) {
                                liquidityStates.push({
                                    liquidity:
                                        lastLiquidityDeposit.liquidity.sub(
                                            liquidityWithdrawn
                                        ),
                                    price: lastLiquidityDeposit.price,
                                });
                            }
                            liquidityWithdrawn =
                                liquidityWithdrawn.sub(liquidityToChange);
                        }
                    }
                    // console.log("Changes should be zero, theyre " + currentChanges[0].toString() + ", " + currentChanges[1].toString());
                    changes[0] = changes[0].add(currentChanges[0]);
                    changes[1] = changes[1].add(currentChanges[1]);
                }
            }
            this.expectedUniV3Changes[0] = this.expectedUniV3Changes[0].add(
                changes[0]
            );
            this.expectedUniV3Changes[1] = this.expectedUniV3Changes[1].add(
                changes[1]
            );
            this.vaultChanges[this.uniV3Vault.address] = [];
            return changes;
        }

        function getMinMaxEstimates(
            value: BigNumber,
            nom: BigNumberish,
            denom: BigNumberish
        ) {
            nom = BigNumber.from(nom);
            denom = BigNumber.from(denom);
            let maxValue = value.mul(denom.add(nom)).div(denom);
            let minValue = value.mul(denom.sub(nom)).div(denom);
            if (maxValue.lt(minValue)) {
                [maxValue, minValue] = [minValue, maxValue];
            }
            return { max: maxValue, min: minValue };
        }

        before(async () => {
            this.setZeroFeesFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    this.targets = options
                        ? options.targets
                        : [
                              this.erc20Vault,
                              this.aaveVault,
                              this.uniV3Vault,
                              this.yearnVault,
                          ];
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
                            depositCallbackAddress:
                                ethers.constants.AddressZero,
                            withdrawCallbackAddress:
                                ethers.constants.AddressZero,
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
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });
        describe("properties", () => {
            it(
                `
                when fees are zero, sum of deposit[i] = sum of withdraw[j]
            `,
                async () => {
                let targets = [
                    this.erc20Vault,
                    this.aaveVault,
                    this.uniV3Vault,
                    this.yearnVault,
                ];
                await this.setZeroFeesFixture({ targets: targets });

                //DEPOSIT
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(10),
                    BigNumber.from(10).pow(15).mul(3),
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
                        await doPullAction.call(this, randomAction, false);
                    }
                }

                if (!this.uniV3Nft.eq(0)) {
                    await this.uniV3Vault.connect(this.deployer).collectEarnings();
                }
                
                await this.uniV3Vault
                    .connect(this.deployer)
                    .reclaimTokens(this.tokensAddresses);

                let lpAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                let tvlBeforeWithdraw = await printVaults.call(this);
                let onlyWithdraw = await this.subject
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

                //PULL EVERYTHING TO ZERO
                for (let i = 1; i < this.targets.length; i++) {
                    let pullAction = await fullPullAction.call(
                        this,
                        this.targets[i]
                    );
                    await printPullAction.call(this, pullAction);
                    await doPullAction.call(this, pullAction, true);
                }

                if (!this.uniV3Nft.eq(0)) {
                    await this.uniV3Vault.connect(this.deployer).collectEarnings();
                }

                await printVaults.call(this);

                await this.uniV3Vault
                    .connect(this.deployer)
                    .reclaimTokens(this.tokensAddresses);
                
                // let liqudityStateBeforeWithdraw = await getLiquidityState.call(this, this.uniV3Vault.address);
                //WITHDRAW
                lpAmount = await this.subject.balanceOf(
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
                if (!(actualWithdraw[0].eq(onlyWithdraw[0]) && actualWithdraw[1].eq(onlyWithdraw[1]))) {
                    console.log(
                        "Planned to withdraw: " +
                            onlyWithdraw[0].toString() +
                            " " +
                            onlyWithdraw[1].toString());
                    console.log(
                        "Withdrawn: " +
                            actualWithdraw[0].toString() +
                            " " +
                            actualWithdraw[1].toString());
                    let minTvlBeforeWithdraw = [BigNumber.from(0), BigNumber.from(0)];
                    for (let tokenIndex = 0; tokenIndex < 2; tokenIndex++) {
                        for (let vaultTvl of tvlBeforeWithdraw) {
                            minTvlBeforeWithdraw[tokenIndex]
                        }
                        
                    }
                     = tvlBeforeWithdraw[0]
                }
                // let liqudityStateAfterWithdraw = await getLiquidityState.call(this, this.uniV3Vault.address);


                // if (this.vaultChanges[this.uniV3Vault.address].length > 0) {
                //     this.vaultChanges[this.uniV3Vault.address].push({
                //         amount: [BigNumber.from(0), BigNumber.from(0)],
                //         timestamp: (await ethers.provider.getBlock("latest")).timestamp,
                //         liquidityStateBefore: liqudityStateBeforeWithdraw,
                //         liquidityStateAfter: liqudityStateAfterWithdraw,
                //     });
                // }

                // await countUniV3Changes.call(this, true);

                //COUNT FEES FROM EVERY VAULT
                let targetFees = [];
                for (let target of this.targets) {
                    let profit = await countFees.call(this, target.address);
                    targetFees.push(profit);
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
                    let actualChanges = actualWithdraw[tokenIndex].sub(
                        depositAmount[tokenIndex]
                    );
                    let expectedFees = BigNumber.from(0);
                    for (let fees of targetFees) {
                        expectedFees = expectedFees.add(fees[tokenIndex]);
                    }

                    const { min: feesMinEstimation, max: feesMaxEstimation } =
                        getMinMaxEstimates(expectedFees, 1, 100);
                    let uniV3ChangeMinEstimation = this.expectedUniV3Changes[
                        tokenIndex
                    ].sub(depositAmount[tokenIndex].div(1000));
                    uniV3ChangeMinEstimation = getMinMaxEstimates(
                        uniV3ChangeMinEstimation,
                        1,
                        10
                    ).min;
                    let uniV3ChangeMaxEstimation = this.expectedUniV3Changes[
                        tokenIndex
                    ].add(depositAmount[tokenIndex].div(1000));
                    uniV3ChangeMaxEstimation = getMinMaxEstimates(
                        uniV3ChangeMaxEstimation,
                        1,
                        10
                    ).max;
                    console.log(
                        feesMinEstimation
                            .add(uniV3ChangeMinEstimation)
                            .toString()
                    );
                    console.log(actualChanges.toString());
                    console.log(
                        this.expectedUniV3Changes[tokenIndex].toString()
                    );
                    console.log(
                        feesMaxEstimation
                            .add(uniV3ChangeMaxEstimation)
                            .toString()
                    );

                    expect(actualChanges).to.be.gt(
                        feesMinEstimation.add(uniV3ChangeMinEstimation)
                    );
                    expect(actualChanges).to.be.lt(
                        feesMaxEstimation.add(uniV3ChangeMaxEstimation)
                    );
                }
                return true;
            });
        });
    }
);
