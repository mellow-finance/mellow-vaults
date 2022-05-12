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
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    AaveVault,
    AaveVault__factory,
    ERC20RootVaultGovernance,
    ERC20Token,
    IIntegrationVault,
    ILendingPool,
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
};

type DeployOptions = {};

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
                        INonfungiblePositionManager,
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
            let uniV3Nft = await this.uniV3Vault.uniV3Nft();
            if (!uniV3Nft.eq(0)) {
                let result = await this.positionManager.positions(
                    uniV3Nft
                );
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
            console.log("MinTvls:");
            let tvlPromises = this.targets.map((target: Vault) => target.tvl());
            let tvlResults = await Promise.all(tvlPromises);
            this.targets.filter((target, index) =>
                process.stdout.write(tvlResults[index][0] + " | ")
            );
            process.stdout.write("\n");
            console.log("MaxTvls:");
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
                if (pullAmount[largerCoinIndex].lt(1) || pullAmount[1 - largerCoinIndex].lt(ratio)) {
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
        };

        async function doRandomEnvironmentChange(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ) {
            let target = randomChoice(this.targets).item;
            if (target == this.aaveVault) {
                sleep(randomInt(10000));
            } else if ((target == this.uniV3Vault) && (this.firstUniV3Pull == false)) {
                let poolSlot0 = await this.uniV3Pool.slot0();
                // console.log(
                //     "Current Ratio:" +
                //         (
                //             await getRatioFromPriceX96(poolSlot0.sqrtPriceX96)
                //         ).toString()
                // );
                let zeroForOne = randomChoice([true, false]).item
                let liquidity = await this.uniV3Pool.liquidity();
                let tickLower = (await this.uniV3Pool.slot0()).tick;
                let priceBetweenTicks = (await this.tickMath.getSqrtRatioAtTick(tickLower)).add(
                    await this.tickMath.getSqrtRatioAtTick(tickLower + 1)
                ).div(2);
                let liquidityToAmount = zeroForOne ? liquidityToY : liquidityToX;
                let minRecieveFromSwapAmount = await liquidityToAmount.call(this, priceBetweenTicks, tickLower + 1, tickLower, liquidity);
                let recieveFromSwapAmount = minRecieveFromSwapAmount.mul(randomInt(1, 10));
                let swapFees = await getFeesFromSwap.call(this, recieveFromSwapAmount, zeroForOne);
                this.uniV3Fees[0] = this.uniV3Fees[0].add(swapFees[0]);
                this.uniV3Fees[1] = this.uniV3Fees[1].add(swapFees[1]);
                let amountOut = await uniSwapTokensGivenOutput(
                    this.swapRouter,
                    this.tokens,
                    this.uniV3PoolFee,
                    zeroForOne,
                    recieveFromSwapAmount,
                );
                // poolSlot0 = await this.uniV3Pool.slot0();
                // console.log(
                //     "Ratio after swap:" +
                //         (
                //             await getRatioFromPriceX96(poolSlot0.sqrtPriceX96)
                //         ).toString()
                // );
            }
        }

        async function liquidityToY(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            sqrtPriceX96:BigNumber, tickUpper:number, tickLower:number, liquidity:BigNumber) {
            let tickLowerPriceX96 = await this.tickMath.getSqrtRatioAtTick(tickLower);
            console.log(liquidity.toString());
            return (sqrtPriceX96.sub(tickLowerPriceX96)).mul(liquidity).div(BigNumber.from(2).pow(96));
        }

        async function liquidityToX(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            sqrtPriceX96:BigNumber, tickUpper:number, tickLower:number, liquidity:BigNumber) {
            let tickUpperPriceX96 = await this.tickMath.getSqrtRatioAtTick(tickUpper);
            // console.log("see tick sqrt change");
            // console.log(tickUpperPriceX96.sub(sqrtPriceX96).toString());
            let smth = tickUpperPriceX96.sub(sqrtPriceX96).mul(BigNumber.from(2).pow(96));
            return liquidity.mul(smth).div(tickUpperPriceX96.mul(sqrtPriceX96));
        }

        async function getFeesFromSwap(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            amount:BigNumber, zeroForOne:boolean,
        ) {
            let currentTick = (await this.uniV3Pool.slot0()).tick;
            let currentPrice = (await this.uniV3Pool.slot0()).sqrtPriceX96;
            let currentTickLiquidity = await this.uniV3Pool.liquidity();
            let fees: BigNumber = BigNumber.from(0);
            let uniV3Nft = await this.uniV3Vault.uniV3Nft();
            let myLiquidity = (await this.positionManager.positions(uniV3Nft)).liquidity;
            while (amount.gt(0)) {
                console.log("amount left: " + amount.toString());
                console.log("current tick: " + currentTick);

                let amountToNextTick;
                if (zeroForOne) {
                    amountToNextTick = await liquidityToX.call(this, currentPrice, currentTick + 1, currentTick, currentTickLiquidity);
                } else {
                    amountToNextTick = await liquidityToY.call(this, currentPrice, currentTick + 1, currentTick, currentTickLiquidity);
                }
                let currentSwapAmount = amount.lt(amountToNextTick) ? amount : amountToNextTick;
                let currentSwapAmountInOtherCoin: BigNumber;
                if (zeroForOne) {
                    currentSwapAmountInOtherCoin = 
                } else {
                    currentSwapAmountInOtherCoin =
                }
                console.log("currentAmount" + currentSwapAmount.toString());
                if ((this.tickUpper > currentTick) && (currentTick >= this.tickLower)) {
                    console.log("+FEES");
                    console.log("liquidities:");
                    console.log(myLiquidity.toString());
                    console.log(currentTickLiquidity.toString());
                    fees = fees.add(currentSwapAmount.mul(myLiquidity).div(currentTickLiquidity).mul(this.uniV3PoolFee).div(1000000));
                }
                amount = amount.sub(currentSwapAmount);
                if (zeroForOne) {
                    currentPrice = await this.tickMath.getSqrtRatioAtTick(currentTick + 1);
                    currentTick += 1;
                    let tickInfo = await this.uniV3Pool.ticks(currentTick)
                    // if (!tickInfo.liquidityNet.eq(0)) {
                    //     console.log("tlNET = " + tickInfo.liquidityNet + ", " + currentTick);
                    // }
                    // assert(tickInfo.liquidityNet.eq(0), "never been here, tick " + currentTick);
                    currentTickLiquidity = currentTickLiquidity.add(tickInfo.liquidityNet);
                } else {
                    currentPrice = await this.tickMath.getSqrtRatioAtTick(currentTick);
                    currentTick -= 1;
                    let tickInfo = await this.uniV3Pool.ticks(currentTick)
                    // if (!tickInfo.liquidityNet.eq(0)) {
                    //     console.log("flNET = " + tickInfo.liquidityNet + ", " + currentTick);
                    // }
                    // assert(tickInfo.liquidityNet.eq(0), "never been here, tick " + currentTick);
                    currentTickLiquidity = currentTickLiquidity.sub(tickInfo.liquidityNet);
                }
            }
            if (zeroForOne) {
                return [BigNumber.from(0), fees];
            } else {
                return [fees, BigNumber.from(0)];
            }
        }

        function getRatioFromPriceX96(priceX96: BigNumber): BigNumber {
            return priceX96.pow(2).div(BigNumber.from(2).pow(192));
        }
        function getReverseRatioFromPriceX96(priceX96: BigNumber): BigNumber {
            return (BigNumber.from(2).pow(192)).div(priceX96.pow(2));
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

        async function getBalance(
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
                let uniV3Nft = await this.uniV3Vault.uniV3Nft();
                if (!uniV3Nft.eq(0)) {
                    let result = await this.positionManager.positions(uniV3Nft);
                    console.log("liquidity");
                    console.log(result["liquidity"].toString());
                    console.log(result["tokensOwed0"].toString());
                    console.log(result["tokensOwed1"].toString());
                    if (result["liquidity"].eq(0)) {
                        return [BigNumber.from(0), BigNumber.from(0)];
                    } else {
                        return [BigNumber.from(1), BigNumber.from(1)];
                    }
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
                options = encodeToBytes(["uint256"], [ethers.constants.Zero]);
            } else if (action.to.address == this.uniV3Vault.address) {
                options = encodeToBytes(
                    ["uint256", "uint256", "uint256"],
                    [
                        ethers.constants.Zero,
                        ethers.constants.Zero,
                        ethers.constants.MaxUint256,
                    ]
                );
            }
            let fromBalanceBefore = await getBalance.call(
                this,
                action.from.address
            );
            let toBalanceBefore = await getBalance.call(
                this,
                action.to.address
            );
            let currentTimestamp = (await ethers.provider.getBlock("latest"))
                .timestamp;
            if (
                action.to.address == this.uniV3Vault.address &&
                this.uniV3VaultIsEmpty
            ) {
                let tickSpacing = await this.uniV3Pool.tickSpacing();
                let currentTick = (await this.uniV3Pool.slot0()).tick;
                let positionLength = randomInt(1, 4);
                let lowestTickAvailible = currentTick - currentTick % tickSpacing - tickSpacing;
                let lowerTick = lowestTickAvailible + tickSpacing * randomInt(0, 4 - positionLength);
                let upperTick = lowerTick + tickSpacing * positionLength; 
                await pullToUniV3Vault.call(this, action.from, {
                    fee: this.uniV3PoolFee,
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    token0Amount: action.amount[0],
                    token1Amount: action.amount[1],
                });
                this.uniV3VaultIsEmpty = false;
            } else {
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
            }
            let fromBalanceAfter = await getBalance.call(
                this,
                action.from.address
            );
            let toBalanceAfter = await getBalance.call(this, action.to.address);
            if (action.from.address == this.uniV3Vault.address) {
                if (fromBalanceAfter[0].eq(0) && fromBalanceAfter[1].eq(0)) {
                    this.uniV3VaultIsEmpty = true;
                }
            }
            this.vaultChanges[action.from.address].push({
                amount: action.amount.map((amount) => amount.mul(-1)),
                timestamp: currentTimestamp,
                balanceBefore: fromBalanceBefore,
                balanceAfter: fromBalanceAfter,
            });
            this.vaultChanges[action.to.address].push({
                amount: action.amount,
                timestamp: currentTimestamp,
                balanceBefore: toBalanceBefore,
                balanceAfter: toBalanceAfter,
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
            let uniV3Nft = await this.uniV3Vault.uniV3Nft();

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
                if (!this.firstUniV3Pull) {
                    await this.uniV3Vault.connect(signer).collectEarnings();
                }
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
                if (!this.firstUniV3Pull) {
                    await this.positionManager.connect(signer).burn(uniV3Nft);
                }
                this.firstUniV3Pull = false;
            });
        }

        async function countProfit(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            vaultAddress: string
        ) {
            let stateChanges = this.vaultChanges[vaultAddress];
            let profit = [];
            if (
                vaultAddress == this.aaveVault.address ||
                vaultAddress == this.yearnVault.address
            ) {
                for (
                    let tokenIndex = 0;
                    tokenIndex < this.tokens.length;
                    tokenIndex++
                ) {
                    let tokenProfit = BigNumber.from(0);
                    for (let i = 1; i < stateChanges.length; i++) {
                        tokenProfit = tokenProfit
                            .add(stateChanges[i].balanceBefore[tokenIndex])
                            .sub(stateChanges[i - 1].balanceAfter[tokenIndex]);
                    }
                    profit.push(tokenProfit);
                }
            } else {
                profit = this.uniV3Fees;
            }
            return profit;
        }

        beforeEach(async () => {
            await this.deploymentFixture();
            this.firstUniV3Pull = true;
            this.uniV3VaultIsEmpty = true;
        });

        describe("properties", () => {
            const setZeroFeesFixture = deployments.createFixture(async () => {
                await this.deploymentFixture();
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
            });

            it("zero fees", async () => {
                await setZeroFeesFixture();
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(10),
                    BigNumber.from(10).pow(18).mul(10),
                ];

                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);
                this.targets = [this.erc20Vault, this.uniV3Vault];
                this.vaultChanges = {};
                for (let x of this.targets) {
                    this.vaultChanges[x.address] = [];
                }
                for (let i = 0; i < 10; i++) {
                    await printVaults.call(this);
                    if (randomInt(2) == 0) {
                        console.log("ENVIRONMENT CHANGED");
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
                await printVaults.call(this);
                console.log("ZABIRAU SVOYE");
                await this.uniV3Vault.collectEarnings();
                await printVaults.call(this);
                for (let i = 1; i < this.targets.length; i++) {
                    let pullAction = await fullPullAction.call(
                        this,
                        this.targets[i]
                    );
                    await printPullAction.call(this, pullAction);
                    await doPullAction.call(this, pullAction);
                }

                await printVaults.call(this);

                let optionsAave = encodeToBytes(
                    ["uint256"],
                    [ethers.constants.Zero]
                );
                let optionsUniV3 = encodeToBytes(
                    ["uint256", "uint256", "uint256"],
                    [
                        ethers.constants.Zero,
                        ethers.constants.Zero,
                        ethers.constants.MaxUint256,
                    ]
                );

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
                            optionsAave,
                            optionsUniV3,
                            randomBytes(4),
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
                            optionsAave,
                            optionsUniV3,
                            randomBytes(4),
                        ]
                    );
                console.log(
                    "Withdrawn: " +
                        actualWithdraw[0].toString() +
                        " " +
                        actualWithdraw[1].toString()
                );

                for (let target of this.targets) {
                    let targetProfit = await countProfit.call(
                        this,
                        target.address
                    );
                    console.log(
                        this.mapVaultsToNames[target.address] +
                            " profit is " +
                            targetProfit[0].toString() +
                            ", " +
                            targetProfit[1].toString()
                    );
                }

                // for (let tokenIndex = 0; tokenIndex < this.tokens.length; tokenIndex++) {
                //     let expectedDeposit = actualWithdraw[tokenIndex].sub(aaveProfit[tokenIndex]).sub(yearnProfit[tokenIndex]);
                //     expect(expectedDeposit).to.be.gt(depositAmount[tokenIndex].mul(99).div(100))
                //     expect(expectedDeposit).to.be.lt(depositAmount[tokenIndex].mul(101).div(100))
                // }
            });

            it("testing", async () => {
                await setZeroFeesFixture();
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(10),
                    BigNumber.from(10).pow(18).mul(10),
                ];

                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);
                this.targets = [this.erc20Vault, this.aaveVault];
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

                let optionsAave = encodeToBytes(
                    ["uint256"],
                    [ethers.constants.Zero]
                );
                let optionsUniV3 = encodeToBytes(
                    ["uint256", "uint256", "uint256"],
                    [
                        ethers.constants.Zero,
                        ethers.constants.Zero,
                        ethers.constants.MaxUint256,
                    ]
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
                            optionsAave,
                            optionsUniV3,
                            randomBytes(4),
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
                            optionsAave,
                            optionsUniV3,
                            randomBytes(4),
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
                await setZeroFeesFixture();
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(10),
                    BigNumber.from(10).pow(18).mul(10),
                ];

                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);
                this.targets = [this.erc20Vault, this.yearnVault];
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

                let optionsAave = encodeToBytes(
                    ["uint256"],
                    [ethers.constants.Zero]
                );
                let optionsUniV3 = encodeToBytes(
                    ["uint256", "uint256", "uint256"],
                    [
                        ethers.constants.Zero,
                        ethers.constants.Zero,
                        ethers.constants.MaxUint256,
                    ]
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
                            optionsAave,
                            optionsUniV3,
                            randomBytes(4),
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
                            optionsAave,
                            optionsUniV3,
                            randomBytes(4),
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
                    console.log("tick " + tickNumber + ", gross is " + tickData.liquidityGross + ", net is " + tickData.liquidityNet);
                }
                
            });

            it("testing tick edges", async () => {
                let currentTick = (await this.uniV3Pool.slot0()).tick;
                let currentPrice = (await this.uniV3Pool.slot0()).sqrtPriceX96;
                let currentTickLiquidity = await this.uniV3Pool.liquidity();
                let upperBound = await this.tickMath.getSqrtRatioAtTick(currentTick + 1);
                let lowerBound = await this.tickMath.getSqrtRatioAtTick(currentTick);
                let upperBoundRatio = getRatioFromPriceX96(upperBound);
                let lowerBoundRatio = getRatioFromPriceX96(lowerBound);
                let currentRatio = getRatioFromPriceX96(currentPrice);
                console.log("current tick: " + currentTick);
                console.log("upper ratio: " + upperBoundRatio.toString());
                console.log("current ratio: " + currentRatio.toString());
                console.log("lower ratio: " + lowerBoundRatio.toString());
                console.log("currentTickLiquidity: " + currentTickLiquidity.toString());
                let yLiquidity = (currentPrice.sub(lowerBound)).mul(currentTickLiquidity).div(BigNumber.from(2).pow(96));
                console.log("yLiquidity");
                console.log(yLiquidity.toString());

                console.log("current tick: " + currentTick);
                console.log("taking from pool all liquidity except 10^12");
                await uniSwapTokensGivenOutput(
                    this.swapRouter,
                    this.tokens,
                    this.uniV3PoolFee,
                    false,
                    yLiquidity.sub(BigNumber.from(10).pow(12)),
                );
                console.log("current tick: " + (await this.uniV3Pool.slot0()).tick);
                console.log("doing swap of 2 * 10^12 token");
                await uniSwapTokensGivenOutput(
                    this.swapRouter,
                    this.tokens,
                    this.uniV3PoolFee,
                    false,
                    BigNumber.from(10).pow(12).add(1),
                );
                console.log("current tick: " + (await this.uniV3Pool.slot0()).tick);
            });

            it("testing pool maths", async () => {
                let slot0 = await this.uniV3Pool.slot0()
                console.log("spacing is " + await this.uniV3Pool.tickSpacing());
                for (let i = 0; i < 15; i++) {
                    slot0 = await this.uniV3Pool.slot0()
                    console.log("tick is " + slot0.tick);
                    console.log("price is " + getRatioFromPriceX96(slot0.sqrtPriceX96).toString());
                    await uniSwapTokensGivenInput(
                        this.swapRouter,
                        this.tokens,
                        this.uniV3PoolFee,
                        false,
                        BigNumber.from(10).pow(13).mul(2),
                    );
                }
            });
            it("testing univ3 edge cases", async () => {
                let optionsAave = encodeToBytes(
                    ["uint256"],
                    [ethers.constants.Zero]
                );
                let optionsUniV3 = encodeToBytes(
                    ["uint256", "uint256", "uint256"],
                    [
                        ethers.constants.Zero,
                        ethers.constants.Zero,
                        ethers.constants.MaxUint256,
                    ]
                );

                await setZeroFeesFixture();
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(3000).mul(200),
                    BigNumber.from(10).pow(18).mul(200),
                ];
                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);

                this.targets = [this.erc20Vault, this.uniV3Vault];
                await printVaults.call(this);

                let slot0 = await this.uniV3Pool.slot0();
                console.log("price is " + getRatioFromPriceX96(slot0.sqrtPriceX96).toString());

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
                            optionsUniV3
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
                            optionsAave,
                            optionsUniV3,
                            randomBytes(4),
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
                            optionsAave,
                            optionsUniV3,
                            randomBytes(4),
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

            it.only("testing univ3", async () => {
                let optionsAave = encodeToBytes(
                    ["uint256"],
                    [ethers.constants.Zero]
                );
                let optionsUniV3 = encodeToBytes(
                    ["uint256", "uint256", "uint256"],
                    [
                        ethers.constants.Zero,
                        ethers.constants.Zero,
                        ethers.constants.MaxUint256,
                    ]
                );
                let optionsYearn = encodeToBytes(
                    ["uint256"],
                    [
                        BigNumber.from(10000),
                    ]
                );

                await setZeroFeesFixture();
                let depositAmount = [
                    BigNumber.from(10).pow(6).mul(3000).mul(200),
                    BigNumber.from(10).pow(18).mul(200),
                ];
                await this.subject
                    .connect(this.deployer)
                    .deposit(depositAmount, 0, []);

                this.targets = [this.erc20Vault, this.uniV3Vault];
                await printVaults.call(this);

                await pullToUniV3Vault.call(this, this.erc20Vault, {
                    fee: this.uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    token0Amount: BigNumber.from(10).pow(6).mul(3000).mul(50),
                    token1Amount: BigNumber.from(10).pow(18).mul(50),
                });
                let slot0 = await this.uniV3Pool.slot0()
                console.log("price is " + getRatioFromPriceX96(slot0.sqrtPriceX96).toString());
                

                let tvlResults = await printVaults.call(this);
                console.log("several big swaps");
                let fees  = [BigNumber.from(0), BigNumber.from(0)];
                let lastliq = BigNumber.from(0);
                for (let i = 0; i < 3; i++) {
                    let curliq = await this.uniV3Pool.liquidity();
                    if (!curliq.eq(lastliq)) {
                        console.log("liquidity changed:");
                        console.log(lastliq.sub(curliq).toString());
                    }
                    lastliq = curliq;
                    console.log("current tick:");
                    console.log((await this.uniV3Pool.slot0()).tick);
                    // let swapAmount = randomBignumber(BigNumber.from(10).pow(8), BigNumber.from(10).pow(8).mul(20));
                    let recieveAmount = BigNumber.from(10).pow(8).mul(50);
                    let swapFees = await getFeesFromSwap.call(this, recieveAmount, true);
                    fees[0] = fees[0].add(swapFees[0]);
                    fees[1] = fees[1].add(swapFees[1]);
                    let amountOut = await uniSwapTokensGivenOutput(
                        this.swapRouter,
                        this.tokens,
                        this.uniV3PoolFee,
                        true,
                        recieveAmount,
                    );
                    // assert(amountOut.gt(0), "AmountOut is zero");

                    // swapAmount = amountOut.mul(1003).div(1000);
                    // swapFees = await getFeesFromSwap.call(this, swapAmount, true);
                    // fees[0] = fees[0].add(swapFees[0]);
                    // fees[1] = fees[1].add(swapFees[1]);
                    // await uniSwapTokensGivenInput(
                    //     this.swapRouter,
                    //     this.tokens,
                    //     this.uniV3PoolFee,
                    //     true,
                    //     swapAmount,
                    // );
                }


                await withSigner(this.subject.address, async (signer) => {
                    
                    let tvlPreFees = await printVaults.call(this);

                    console.log("collect fees");
                    await this.uniV3Vault.connect(signer).collectEarnings();

                    let tvlPostFees = await printVaults.call(this);
                    
                    console.log("fees earned");
                    let feesEarned = [tvlPostFees[0][0][0].sub(tvlPreFees[0][0][0]), tvlPostFees[0][0][1].sub(tvlPreFees[0][0][1])]
                    console.log(feesEarned[0].toString() + " " + feesEarned[1].toString());
                    console.log(fees.toString())

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
                            optionsAave,
                            optionsUniV3,
                            optionsYearn,
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
                            optionsAave,
                            optionsUniV3,
                            optionsYearn,
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
