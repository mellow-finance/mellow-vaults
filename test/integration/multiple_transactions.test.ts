import hre, { getNamedAccounts } from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    compareAddresses,
    encodeToBytes,
    mint,
    randomAddress,
    randomChoice,
    sleep,
    uniSwapTokensGivenOutput,
    withSigner,
} from "../library/Helpers";
import { contract, TestContext } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { YearnVault } from "../types/YearnVault";
import { ERC20Vault } from "../types/ERC20Vault";
import {
    setupVault,
    combineVaults,
    ALLOW_MASK,
    TRANSACTION_GAS_LIMITS,
} from "../../deploy/0000_utils";
import { expect, assert } from "chai";
import { abi as INonfungiblePositionManagerABI } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    AaveVault,
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
import { randomBytes, randomInt } from "crypto";
import { BigNumberish } from "ethers";
import { deployMathTickTest } from "../library/Deployments";

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
    mellowOracle: MellowOracle;
    targets: IntegrationVault[];
    aTokens: ERC20Token[];
    yTokens: ERC20Token[];
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

                    // tokens used in vaults
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

                    // deploy subvaults and create rootvault
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    this.erc20VaultNft = startNft;
                    this.aaveVaultNft = startNft + 1;
                    this.uniV3VaultNft = startNft + 2;
                    this.yearnVaultNft = startNft + 3;
                    this.erc20RootVaultNft = startNft + 4;
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
                    const uniV3Helper = await ethers.getContract("UniV3Helper");
                    this.uniV3PoolFee = 3000;
                    this.uniV3PoolFeeDenominator = 1000000;
                    await setupVault(
                        hre,
                        this.uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                this.tokensAddresses,
                                this.deployer.address,
                                this.uniV3PoolFee,
                                uniV3Helper.address,
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
                    const erc20VaultAddress = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.erc20VaultNft
                    );
                    const aaveVaultAddress = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.aaveVaultNft
                    );
                    const uniV3VaultAddress = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.uniV3VaultNft
                    );
                    const yearnVaultAddress = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.yearnVaultNft
                    );
                    const erc20RootVaultAddress = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.yearnVaultNft + 1
                    );
                    this.subject = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVaultAddress
                    );
                    this.erc20Vault = (await ethers.getContractAt(
                        "ERC20Vault",
                        erc20VaultAddress
                    )) as ERC20Vault;
                    this.aaveVault = (await ethers.getContractAt(
                        "AaveVault",
                        aaveVaultAddress
                    )) as AaveVault;
                    this.uniV3Vault = (await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3VaultAddress
                    )) as UniV3Vault;
                    this.yearnVault = (await ethers.getContractAt(
                        "YearnVault",
                        yearnVaultAddress
                    )) as YearnVault;
                    this.pullExistentials =
                        await this.subject.pullExistentials();

                    // allow deployer to deposit in vault
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    // mint tokens and allow them to vault
                    await mint(
                        "USDC",
                        this.deployer.address,
                        BigNumber.from(10).pow(18).mul(300)
                    );
                    await mint(
                        "WETH",
                        this.deployer.address,
                        BigNumber.from(10).pow(18).mul(300)
                    );
                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );

                    // aaveVault related
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
                    this.optionsAave = encodeToBytes(
                        ["uint256"],
                        [ethers.constants.Zero]
                    );

                    // yearnVault related
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
                    this.optionsYearn = encodeToBytes(
                        ["uint256"],
                        [BigNumber.from(10000)]
                    );

                    //DELETE
                    this.mapVaultsToNames = {};
                    this.mapVaultsToNames[this.erc20Vault.address] =
                        "zeroVault";
                    this.mapVaultsToNames[this.aaveVault.address] = "aaveVault";
                    this.mapVaultsToNames[this.yearnVault.address] =
                        "yearnVault";
                    this.mapVaultsToNames[this.uniV3Vault.address] =
                        "uniV3Vault";

                    // uniV3Vault related
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
                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManagerABI,
                        uniswapV3PositionManager
                    );
                    this.swapRouter = await ethers.getContractAt(
                        ISwapRouter,
                        uniswapV3Router
                    );
                    this.uniV3Fees = [BigNumber.from(0), BigNumber.from(0)];
                    this.tickMath = await deployMathTickTest();
                    this.expectedUniV3Changes = [
                        BigNumber.from(0),
                        BigNumber.from(0),
                    ];
                    this.uniV3Nft = BigNumber.from(0);
                    this.uniV3VaultIsEmpty = true;
                    this.optionsUniV3 = encodeToBytes(
                        ["uint256", "uint256", "uint256"],
                        [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                            ethers.constants.MaxUint256,
                        ]
                    );

                    return this.subject;
                }
            );
        });

        // return tvls of every vault
        async function getVaults(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ) {
            return await Promise.all(
                this.targets.map((target) => target.tvl())
            );
        }

        // generates random PullAction, which will result in vault state change
        async function randomPullAction(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ): Promise<PullAction> {
            let tvls = await Promise.all(
                this.targets.map((target) => target.tvl())
            );
            let nonEmptyVaults = this.targets.filter((_, index) => {
                return (
                    tvls[index][0][0].gt(this.pullExistentials[0]) ||
                    tvls[index][0][1].gt(this.pullExistentials[1])
                );
            });
            let pullTarget = randomChoice(nonEmptyVaults).item;
            let pullTargetIndex = this.targets.indexOf(pullTarget);
            let random = randomInt(1, 4);
            let pullAmount = this.tokens.map((_, index) => {
                if (pullTarget == this.uniV3Vault) {
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
                // mint will fail if minting position liquidity is zero
                if (
                    this.uniV3VaultIsEmpty &&
                    (pullAmount[0].lt(this.pullExistentials[0]) ||
                        pullAmount[1].lt(this.pullExistentials[1]))
                ) {
                    pushCandidates = pushCandidates.filter(
                        (target: Vault) => target != this.uniV3Vault
                    );
                }
                if (pushCandidates.length == 0) {
                    return await randomPullAction.call(this);
                }
                pushTarget = randomChoice(pushCandidates).item;
            } else if (pullTarget == this.uniV3Vault) {
                // to make sure 0 liquidity left
                if (
                    tvls[pullTargetIndex][1][0].eq(pullAmount[0]) &&
                    tvls[pullTargetIndex][1][1].eq(pullAmount[1])
                ) {
                    pullAmount = pullAmount.map((amount) => amount.mul(2));
                }
            }
            return { from: pullTarget, to: pushTarget, amount: pullAmount };
        }

        // makes something that could affect deposited liqudity
        // for univ3 its a swap, for aave its a sleep
        async function doRandomEnvironmentChange(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ) {
            let target = randomChoice(this.targets).item;
            if (target == this.aaveVault) {
                await sleep(randomInt(10000));
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

        // calculates fees earned by position after swap
        async function getFeesFromSwap(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            amount: BigNumber,
            zeroForOne: boolean
        ) {
            let { tick: currentTick, sqrtPriceX96: currentPrice } =
                await this.uniV3Pool.slot0();
            let currentTickLiquidity = await this.uniV3Pool.liquidity();
            let fees: BigNumber = BigNumber.from(0);
            if (this.uniV3Nft.eq(0)) {
                return [BigNumber.from(0), BigNumber.from(0)];
            }
            let myLiquidity = (
                await this.positionManager.positions(this.uniV3Nft)
            ).liquidity;

            while (amount.gt(0)) {
                let liqudityToToken;
                if (zeroForOne) {
                    liqudityToToken = liquidityToX;
                } else {
                    liqudityToToken = liquidityToY;
                }
                let amountToNextTick = await liqudityToToken.call(
                    this,
                    currentPrice,
                    currentTick + 1,
                    currentTick,
                    currentTickLiquidity
                );

                let currentSwapAmount = amount.lt(amountToNextTick)
                    ? amount
                    : amountToNextTick;
                let sqrtPriceAfterTokenChange, tokenAmountUsedInSwap;
                if (zeroForOne) {
                    sqrtPriceAfterTokenChange = sqrtPriceAfterXChange;
                    tokenAmountUsedInSwap = yAmountUsedInSwap;
                } else {
                    sqrtPriceAfterTokenChange = sqrtPriceAfterYChange;
                    tokenAmountUsedInSwap = xAmountUsedInSwap;
                }
                let newPrice = sqrtPriceAfterTokenChange(
                    currentPrice,
                    currentSwapAmount,
                    currentTickLiquidity
                );
                let currentSwapAmountInOtherCoin = tokenAmountUsedInSwap(
                    currentPrice,
                    newPrice,
                    currentTickLiquidity
                );

                if (
                    this.tickUpper > currentTick &&
                    currentTick >= this.tickLower
                ) {
                    fees = fees.add(
                        currentSwapAmountInOtherCoin
                            .mul(myLiquidity)
                            .mul(this.uniV3PoolFee)
                            .div(currentTickLiquidity)
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
                    currentTickLiquidity = currentTickLiquidity.add(
                        tickInfo.liquidityNet
                    );
                } else {
                    currentPrice = await this.tickMath.getSqrtRatioAtTick(
                        currentTick
                    );
                    currentTick -= 1;
                    let tickInfo = await this.uniV3Pool.ticks(currentTick);
                    currentTickLiquidity = currentTickLiquidity.sub(
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

        // limits price with lower and upper tick range
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

        // generates PullAction with given pullTarget and pushTarget = zeroVault
        async function fullPullAction(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            pullTarget: IntegrationVault
        ): Promise<PullAction> {
            let tvls = await pullTarget.tvl();
            let pullAmount = this.tokens.map((token, index) =>
                BigNumber.from(tvls[1][index])
            );
            if (pullTarget == this.uniV3Vault) {
                pullAmount = pullAmount.map((amount) => amount.mul(2));
            }
            return {
                from: pullTarget,
                to: this.erc20Vault,
                amount: pullAmount,
            };
        }

        // returns data representing state of the liquidity in vault
        // a/y Tokens balance or [position liquidity, sqrtPriceX96]
        async function getLiquidityState(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            vaultAddress: string
        ) {
            if (vaultAddress == this.aaveVault.address) {
                return Promise.all(
                    this.aTokens.map((aToken) => aToken.balanceOf(vaultAddress))
                );
            } else if (vaultAddress == this.yearnVault.address) {
                return Promise.all(
                    this.yTokens.map((yToken) => yToken.balanceOf(vaultAddress))
                );
            } else if (vaultAddress == this.uniV3Vault.address) {
                let price = (await this.uniV3Pool.slot0()).sqrtPriceX96;
                let realNft = await this.uniV3Vault.uniV3Nft();
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

        // performs PullAction, logging liqudity states before and after
        async function doPullAction(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            action: PullAction
        ) {
            let options: any = [];
            if (action.to.address == this.aaveVault.address) {
                options = this.optionsAave;
            } else if (action.to.address == this.uniV3Vault.address) {
                options = this.optionsUniV3;
            } else if (action.to.address == this.yearnVault.address) {
                options = this.optionsYearn;
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
                // opens uniV3 position if vault is empty
                let tickSpacing = await this.uniV3Pool.tickSpacing();
                let currentTick = (await this.uniV3Pool.slot0()).tick;
                let positionLength = randomInt(1, 4);
                let lowestTickAvailible =
                    currentTick - (currentTick % tickSpacing) - tickSpacing;
                let lowerTick =
                    lowestTickAvailible +
                    tickSpacing * randomInt(0, 4 - positionLength);
                let upperTick = lowerTick + tickSpacing * positionLength;
                await openUniV3Position.call(this, action.from, {
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
                if (fromLiquidityStateAfter[0].eq(0)) {
                    this.uniV3VaultIsEmpty = true;
                    await countImpermanentLossDuringLastPosition.call(this);
                    await checkInvariant.call(this, false);
                }
            }
        }

        // mint postion's NFT with given parameters
        async function openUniV3Position(
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

        // count fees earned by given vault based on logs
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
                fees = this.uniV3Fees;
            }
            return fees;
        }

        // counts changes in positions token distribution caused by swaps
        async function countImpermanentLoss(
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
                let withdrawY = await liquidityToY.call(
                    this,
                    withdrawPrice,
                    this.tickUpper,
                    this.tickLower,
                    liquidity
                );
                return [withdrawX.sub(depositX), withdrawY.sub(depositY)];
            }
            return [BigNumber.from(0), BigNumber.from(0)];
        }

        // calculates impermanent losses caused by swaps in pool since position was open
        async function countImpermanentLossDuringLastPosition(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext
        ) {
            let liquidityStates: any[] = [];
            let stateChanges = this.vaultChanges[this.uniV3Vault.address];
            let changes = [BigNumber.from(0), BigNumber.from(0)];
            for (let i = 0; i < stateChanges.length; i++) {
                let liquidityBefore = stateChanges[i].liquidityStateBefore[0];
                let liquidityAfter = stateChanges[i].liquidityStateAfter[0];
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
                                    await countImpermanentLoss.call(
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

        // returns two values, deviating by vaulue * nom / denom from given one
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

        // checks that total token amounts deviated from deposit amount by
        // totalFeesAmount + totalImpermanentLossAmount
        async function checkInvariant(
            this: TestContext<ERC20RootVault, DeployOptions> & CustomContext,
            doWithdraw: boolean
        ) {
            let tokensAmount = [BigNumber.from(0), BigNumber.from(0)];

            if (doWithdraw) {
                // count withdrawn amount
                await this.uniV3Vault
                    .connect(this.deployer)
                    .reclaimTokens(this.tokensAddresses);

                let lpAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                tokensAmount = await this.subject
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
                        lpAmount,
                        [0, 0],
                        [
                            randomBytes(4),
                            this.optionsAave,
                            this.optionsUniV3,
                            this.optionsYearn,
                        ]
                    );
            } else {
                // count tvl sum
                let tvls = await getVaults.call(this);
                for (let tvl of tvls) {
                    tokensAmount[0] = tokensAmount[0].add(tvl[0][0]);
                    tokensAmount[1] = tokensAmount[1].add(tvl[0][1]);
                }
            }

            // count fees from each vault
            let targetFees = [];
            for (let target of this.targets) {
                let fees = await countFees.call(this, target.address);
                targetFees.push(fees);
            }

            // expect debit equals credit
            for (
                let tokenIndex = 0;
                tokenIndex < this.tokens.length;
                tokenIndex++
            ) {
                let actualChanges = tokensAmount[tokenIndex].sub(
                    this.depositAmount[tokenIndex]
                );
                let expectedFees = BigNumber.from(0);
                for (let fees of targetFees) {
                    expectedFees = expectedFees.add(fees[tokenIndex]);
                }

                const { min: feesMinEstimation, max: feesMaxEstimation } =
                    getMinMaxEstimates(expectedFees, 1, 100);
                let uniV3ChangeMinEstimation = this.expectedUniV3Changes[
                    tokenIndex
                ].sub(this.depositAmount[tokenIndex].div(10000));
                uniV3ChangeMinEstimation = getMinMaxEstimates(
                    uniV3ChangeMinEstimation,
                    1,
                    10
                ).min;
                let uniV3ChangeMaxEstimation = this.expectedUniV3Changes[
                    tokenIndex
                ].add(this.depositAmount[tokenIndex].div(10000));
                uniV3ChangeMaxEstimation = getMinMaxEstimates(
                    uniV3ChangeMaxEstimation,
                    1,
                    10
                ).max;

                expect(actualChanges).to.be.gt(
                    feesMinEstimation.add(uniV3ChangeMinEstimation)
                );
                expect(actualChanges).to.be.lt(
                    feesMaxEstimation.add(uniV3ChangeMaxEstimation)
                );
            }
            return tokensAmount;
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

                    // disable ChainlinkOracle, doesnt work in tests
                    let uniV3Oracle = await ethers.getContract("UniV3Oracle");
                    await deployments.deploy("MellowOracle", {
                        from: this.deployer.address,
                        args: [
                            ethers.constants.AddressZero,
                            uniV3Oracle.address,
                            ethers.constants.AddressZero,
                        ],
                        log: true,
                        autoMine: true,
                        ...TRANSACTION_GAS_LIMITS,
                    });
                    let mellowOracle: MellowOracle = await ethers.getContract(
                        "MellowOracle"
                    );
                    this.uniV3VaultGovernance = await ethers.getContract(
                        "UniV3VaultGovernance"
                    );
                    await this.uniV3VaultGovernance
                        .connect(this.admin)
                        .stageDelayedProtocolParams({
                            positionManager: this.positionManager.address,
                            oracle: mellowOracle.address,
                        });

                    // disable fees
                    let erc20RootVaultGovernance: ERC20RootVaultGovernance =
                        await ethers.getContract("ERC20RootVaultGovernance");

                    await erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.erc20RootVaultNft, {
                            strategyTreasury: randomAddress(),
                            strategyPerformanceTreasury: randomAddress(),
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
                    await this.uniV3VaultGovernance
                        .connect(this.admin)
                        .commitDelayedProtocolParams();
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitParams();
                    this.vaultChanges = {};
                    for (let x of this.targets) {
                        this.vaultChanges[x.address] = [];
                    }
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("makes a lot of random pulls and swaps, then checks if withdrawn amount is correct", () => {
            it(`passes`, async () => {
                let targets = [
                    this.erc20Vault,
                    this.aaveVault,
                    this.uniV3Vault,
                    this.yearnVault,
                ];
                await this.setZeroFeesFixture({ targets: targets });

                // deposit
                this.depositAmount = [
                    BigNumber.from(10).pow(6).mul(1000),
                    BigNumber.from(10).pow(15).mul(300),
                ];
                await this.subject
                    .connect(this.deployer)
                    .deposit(this.depositAmount, 0, []);

                // random actions
                for (let i = 0; i < 100; i++) {
                    if (randomInt(2) == 0) {
                        await doRandomEnvironmentChange.call(this);
                    } else {
                        let randomAction = await randomPullAction.call(this);
                        await doPullAction.call(this, randomAction);
                    }
                }

                // pull everything to zeroVault
                for (let i = 1; i < this.targets.length; i++) {
                    let pullAction = await fullPullAction.call(
                        this,
                        this.targets[i]
                    );
                    await doPullAction.call(this, pullAction);
                    await this.targets[i]
                        .connect(this.deployer)
                        .reclaimTokens(this.tokensAddresses);
                }

                // withdraw and check final invariant
                await checkInvariant.call(this, true);

                // make sure nothing left
                let tvls = await getVaults.call(this);
                for (let tvl of tvls) {
                    for (
                        let tokenIndex = 0;
                        tokenIndex < this.tokens.length;
                        tokenIndex++
                    ) {
                        expect(tvl[0][tokenIndex].lt(10)).to.be.true;
                        expect(tvl[1][tokenIndex].lt(10)).to.be.true;
                    }
                }
            });
        });
    }
);
