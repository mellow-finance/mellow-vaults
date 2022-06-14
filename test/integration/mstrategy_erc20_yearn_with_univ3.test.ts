import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    randomAddress,
    sleep,
} from "../library/Helpers";
import { contract } from "../library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    MStrategy,
    ProtocolGovernance,
    UniV3Vault,
    ERC20RootVaultGovernance,
    ISwapRouter as SwapRouterInterface,
    IUniswapV3Pool,
} from "../types";
import { setupVault, combineVaults, ALLOW_MASK } from "../../deploy/0000_utils";
import { expect } from "chai";
import { Contract } from "@ethersproject/contracts";
import { OracleParamsStruct, RatioParamsStruct } from "../types/MStrategy";
import Common from "../library/Common";
import { assert } from "console";
import { randomBytes } from "crypto";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { TickMath } from "@uniswap/v3-sdk";
import Exceptions from "../library/Exceptions";

const UNIV3_FEE = 3000; // corresponds to 0.05% fee in UniV3 pool

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    uniV3Vault: UniV3Vault;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    usdcDeployerSupply: BigNumber;
    wethDeployerSupply: BigNumber;
    swapRouter: SwapRouterInterface;
};

type DeployOptions = {};

class RebalanceChecker {
    x: BigNumber = BigNumber.from(0);
    y: BigNumber = BigNumber.from(0);
    lower: number = 0;
    upper: number = 0;
    fee: number = 0;

    DENOMINATOR = BigNumber.from(10).pow(9);

    constructor(
        token0: BigNumber,
        token1: BigNumber,
        tickMin: number,
        tickMax: number,
        fee: number = 0
    ) {
        this.x = token0;
        this.y = token1;
        this.lower = tickMin;
        this.upper = tickMax;
        this.fee = fee;
    }

    rebalance(tick: number) {
        var price = BigNumber.from(Math.floor(1.0001 ** tick));

        var xFraction = this.calculateFractionToX(tick);
        if (xFraction.lt(0)) {
            xFraction = BigNumber.from(0);
        }
        if (xFraction.gt(this.DENOMINATOR)) {
            xFraction = this.DENOMINATOR;
        }

        var yFraction = this.DENOMINATOR.sub(xFraction);

        var dv = yFraction.mul(price).mul(this.x).sub(xFraction.mul(this.y));
        if (dv.gt(0)) {
            var dx = dv.div(price);
            this.x = this.x.sub(dx.div(this.DENOMINATOR));
            var dy = dx.mul(price).mul(1 - this.fee);
            this.y = this.y.add(dy.div(this.DENOMINATOR));
        } else if (dv.lt(0)) {
            var dy = dv.abs();
            this.y = this.y.sub(dy.div(this.DENOMINATOR));
            var dx = dy.mul(1 - this.fee).div(price);
            this.x = this.x.add(dx.div(this.DENOMINATOR));
        }

        return {
            newToken0: this.x,
            newToken1: this.y,
        };
    }

    calculateFractionToX(tick: number) {
        return this.DENOMINATOR.mul(this.upper - tick).div(
            this.upper - this.lower
        );
    }
}

contract<MStrategy, DeployOptions, CustomContext>(
    "Integration__mstrategy_with_UniV3Vault",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;
                    const tokens = [this.weth.address, this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let erc20VaultNft = startNft;
                    let univ3VaultNft = startNft + 1;
                    let yearnVaultNft = startNft + 2;

                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );
                    let uniV3Helper = (await ethers.getContract("UniV3Helper"))
                        .address;
                    await setupVault(
                        hre,
                        univ3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                UNIV3_FEE,
                                uniV3Helper,
                            ],
                        }
                    );

                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

                    await combineVaults(
                        hre,
                        yearnVaultNft + 1,
                        [erc20VaultNft, univ3VaultNft, yearnVaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );

                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );
                    const uniV3Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        univ3VaultNft
                    );
                    const yearnVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        yearnVaultNft
                    );

                    const erc20RootVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        yearnVaultNft + 1
                    );

                    this.erc20RootVault = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );
                    this.erc20Vault = (await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    )) as ERC20Vault;
                    this.uniV3Vault = (await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault
                    )) as UniV3Vault;

                    this.yearnVault = (await ethers.getContractAt(
                        "YearnVault",
                        yearnVault
                    )) as YearnVault;

                    await this.erc20RootVault
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    const usdcForUniV3Mint = BigNumber.from(10)
                        .pow(6)
                        .mul(3000)
                        .sub(991);
                    const wethForUniV3Mint =
                        BigNumber.from("977868805654895061");

                    this.usdcDeployerSupply = BigNumber.from(10)
                        .pow(6)
                        .mul(3000);
                    this.wethDeployerSupply = BigNumber.from(10).pow(18);
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

                    const { uniswapV3PositionManager } =
                        await getNamedAccounts();

                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    const result = await mintUniV3Position_USDC_WETH({
                        fee: UNIV3_FEE,
                        tickLower: -887220,
                        tickUpper: 887220,
                        usdcAmount: usdcForUniV3Mint,
                        wethAmount: wethForUniV3Mint,
                    });

                    await this.positionManager.functions[
                        "safeTransferFrom(address,address,uint256)"
                    ](
                        this.deployer.address,
                        this.uniV3Vault.address,
                        result.tokenId
                    );

                    await this.weth.approve(
                        this.erc20RootVault.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.erc20RootVault.address,
                        ethers.constants.MaxUint256
                    );

                    this.erc20RootVaultNft = yearnVault + 1;
                    this.strategyTreasury = randomAddress();
                    this.strategyPerformanceTreasury = randomAddress();

                    this.mellowOracle = await ethers.getContract(
                        "MellowOracle"
                    );

                    /*
                     * Deploy MStrategy
                     */
                    const { uniswapV3Router } = await getNamedAccounts();
                    const mStrategy = await (
                        await ethers.getContractFactory("MStrategy")
                    ).deploy(uniswapV3PositionManager, uniswapV3Router);
                    const params = [
                        tokens,
                        erc20Vault,
                        yearnVault,
                        UNIV3_FEE,
                        this.mStrategyAdmin.address,
                    ];
                    const address = await mStrategy.callStatic.createStrategy(
                        ...params
                    );
                    await mStrategy.createStrategy(...params);
                    this.subject = await ethers.getContractAt(
                        "MStrategy",
                        address
                    );

                    /*
                     * Configure oracles for the MStrategy
                     */
                    const oracleParams: OracleParamsStruct = {
                        oracleObservationDelta: 15,
                        maxTickDeviation: 10000,
                        maxSlippageD: Math.round(0.1 * 10 ** 9),
                    };
                    const ratioParams: RatioParamsStruct = {
                        tickMin: 198240 - 15000,
                        tickMax: 198240 + 15000,
                        erc20MoneyRatioD: Math.round(0.1 * 10 ** 9),
                        minTickRebalanceThreshold: 0,
                        tickNeighborhood: 60,
                        tickIncrease: 180,
                        minErc20MoneyRatioDeviation0D: Math.round(
                            0.01 * 10 ** 9
                        ),
                        minErc20MoneyRatioDeviation1D: Math.round(
                            0.01 * 10 ** 9
                        ),
                    };
                    let txs = [];
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "setOracleParams",
                            [oracleParams]
                        )
                    );
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "setRatioParams",
                            [ratioParams]
                        )
                    );
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .functions["multicall"](txs);

                    this.swapRouter = await ethers.getContractAt(
                        ISwapRouter,
                        uniswapV3Router
                    );
                    await this.usdc.approve(
                        this.swapRouter.address,
                        ethers.constants.MaxUint256
                    );
                    await this.weth.approve(
                        this.swapRouter.address,
                        ethers.constants.MaxUint256
                    );

                    await this.vaultRegistry
                        .connect(this.admin)
                        .adminApprove(
                            this.subject.address,
                            await this.erc20Vault.nft()
                        );
                    await this.vaultRegistry
                        .connect(this.admin)
                        .adminApprove(
                            this.subject.address,
                            await this.yearnVault.nft()
                        );
                    await this.vaultRegistry
                        .connect(this.admin)
                        .adminApprove(
                            this.subject.address,
                            await this.uniV3Vault.nft()
                        );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        const setNonZeroFeesFixture = deployments.createFixture(async () => {
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
                    managementFee: BigNumber.from(10).pow(5),
                    performanceFee: BigNumber.from(10).pow(5),
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
                withdrawLimit: Common.D18.mul(100),
            };
            await this.protocolGovernance
                .connect(this.admin)
                .stageParams(params);
            await sleep(this.governanceDelay);
            await this.protocolGovernance.connect(this.admin).commitParams();
        });

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
                    managementFee: BigNumber.from(0),
                    performanceFee: BigNumber.from(0),
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
                withdrawLimit: Common.D18.mul(100),
            };
            await this.protocolGovernance
                .connect(this.admin)
                .stageParams(params);
            await sleep(this.governanceDelay);
            await this.protocolGovernance.connect(this.admin).commitParams();
        });

        const generateRandomBignumber = (limit: BigNumber) => {
            assert(limit.gt(0), "Bignumber underflow");
            const bytes =
                "0x" + randomBytes(limit._hex.length * 2).toString("hex");
            const result = BigNumber.from(bytes).mod(limit);
            return result;
        };

        const generateArraySplit = (
            w: BigNumber,
            n: number,
            from: BigNumber
        ) => {
            assert(n >= 0, "Zero length array");
            var result: BigNumber[] = [];
            if (w.lt(from.mul(n))) {
                throw "Weight underflow";
            }

            for (var i = 0; i < n; i++) {
                result.push(BigNumber.from(from));
                w = w.sub(from);
            }

            var splits: BigNumber[] = [BigNumber.from(0)];
            for (var i = 0; i < n - 1; i++) {
                splits.push(generateRandomBignumber(w.add(1)));
            }

            splits = splits.sort((x, y) => {
                return x.lt(y) ? -1 : 1;
            });

            var deltas: BigNumber[] = [];
            for (var i = 0; i < n - 1; i++) {
                deltas.push(splits[i + 1].sub(splits[i]));
                w = w.sub(deltas[i]);
            }
            deltas.push(w);

            for (var i = 0; i < n; i++) {
                result[i] = result[i].add(deltas[i]);
            }
            return result;
        };

        const getSqrtPriceX96 = async () => {
            const poolAddress = await this.uniV3Vault.pool();
            const pool: IUniswapV3Pool = await ethers.getContractAt(
                "IUniswapV3Pool",
                poolAddress
            );
            return (await pool.slot0()).sqrtPriceX96;
        };

        const increasePoolCardinality = async (amount: BigNumber) => {
            const poolAddress = await this.uniV3Vault.pool();
            const pool: IUniswapV3Pool = await ethers.getContractAt(
                "IUniswapV3Pool",
                poolAddress
            );
            await pool.increaseObservationCardinalityNext(amount);
        };

        const push = async (
            delta: BigNumber,
            from: string,
            to: string,
            tokenName: string
        ) => {
            const n = 20;
            const amounts = generateArraySplit(
                delta,
                n,
                BigNumber.from(10).pow(6)
            );
            await mint(tokenName, this.deployer.address, delta);
            for (var i = 0; i < n; i++) {
                await this.swapRouter.exactInputSingle({
                    tokenIn: from,
                    tokenOut: to,
                    fee: UNIV3_FEE,
                    recipient: this.deployer.address,
                    deadline: ethers.constants.MaxUint256,
                    amountIn: amounts[i],
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0,
                });
            }

            const usdcAmount = BigNumber.from(10).pow(6).mul(3000);
            const wethAmount = BigNumber.from(10).pow(18);
            await mint("USDC", this.deployer.address, usdcAmount);
            await mint("WETH", this.deployer.address, wethAmount);

            await this.erc20RootVault.deposit(
                [usdcAmount, wethAmount],
                BigNumber.from(0),
                []
            );
            await this.subject
                .connect(this.mStrategyAdmin)
                .manualPull(
                    this.erc20Vault.address,
                    this.uniV3Vault.address,
                    [usdcAmount, wethAmount],
                    []
                );
        };

        const pushPriceDown = async (delta: BigNumber) => {
            await push(delta, this.usdc.address, this.weth.address, "USDC");
        };

        const pushPriceUp = async (delta: BigNumber) => {
            await push(delta, this.weth.address, this.usdc.address, "WETH");
        };

        const getBestPrice = async () => {
            const { pricesX96 } = await this.mellowOracle.priceX96(
                this.usdc.address,
                this.weth.address,
                0x28
            );
            var result = BigNumber.from(0);
            for (var i = 0; i < pricesX96.length; i++) {
                result = result.add(pricesX96[i]);
            }
            return result.div(pricesX96.length);
        };

        const getLiquidityForAmount0 = (
            sqrtRatioAX96: BigNumber,
            sqrtRatioBX96: BigNumber,
            amount0: BigNumber
        ) => {
            if (sqrtRatioAX96.gt(sqrtRatioBX96)) {
                var tmp = sqrtRatioAX96;
                sqrtRatioAX96 = sqrtRatioBX96;
                sqrtRatioBX96 = tmp;
            }
            var intermediate = sqrtRatioAX96.mul(sqrtRatioBX96).div(Common.Q96);
            return amount0
                .mul(intermediate)
                .div(sqrtRatioBX96.sub(sqrtRatioAX96));
        };

        const getLiquidityForAmount1 = (
            sqrtRatioAX96: BigNumber,
            sqrtRatioBX96: BigNumber,
            amount1: BigNumber
        ) => {
            if (sqrtRatioAX96.gt(sqrtRatioBX96)) {
                var tmp = sqrtRatioAX96;
                sqrtRatioAX96 = sqrtRatioBX96;
                sqrtRatioBX96 = tmp;
            }
            return amount1
                .mul(Common.Q96)
                .div(sqrtRatioBX96.sub(sqrtRatioAX96));
        };

        const getLiquidityByTokenAmounts = async (
            amount0: BigNumber,
            amount1: BigNumber
        ) => {
            const { tickLower, tickUpper } =
                await this.positionManager.positions(
                    await this.uniV3Vault.nft()
                );
            var sqrtRatioX96 = await getSqrtPriceX96();
            var sqrtRatioAX96 = BigNumber.from(
                TickMath.getSqrtRatioAtTick(tickLower).toString(10)
            );
            var sqrtRatioBX96 = BigNumber.from(
                TickMath.getSqrtRatioAtTick(tickUpper).toString(10)
            );

            if (sqrtRatioAX96.gt(sqrtRatioBX96)) {
                var tmp = sqrtRatioAX96;
                sqrtRatioAX96 = sqrtRatioBX96;
                sqrtRatioBX96 = tmp;
            }
            var liquidity = BigNumber.from(0);
            if (sqrtRatioX96.lte(sqrtRatioAX96)) {
                liquidity = getLiquidityForAmount0(
                    sqrtRatioAX96,
                    sqrtRatioBX96,
                    amount0
                );
            } else if (sqrtRatioX96 < sqrtRatioBX96) {
                const liquidity0 = getLiquidityForAmount0(
                    sqrtRatioX96,
                    sqrtRatioBX96,
                    amount0
                );
                const liquidity1 = getLiquidityForAmount1(
                    sqrtRatioAX96,
                    sqrtRatioX96,
                    amount1
                );

                liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
            } else {
                liquidity = getLiquidityForAmount1(
                    sqrtRatioAX96,
                    sqrtRatioBX96,
                    amount1
                );
            }
            return liquidity;
        };

        describe("Multiple price swappings and rebalances in mstrategy", () => {
            it("change liquidity only on fees", async () => {
                await setNonZeroFeesFixture();
                const usdcAmountForDeposit = this.usdcDeployerSupply;
                const wethAmountForDeposit = this.wethDeployerSupply;

                await this.erc20RootVault
                    .connect(this.deployer)
                    .deposit(
                        [usdcAmountForDeposit, wethAmountForDeposit],
                        0,
                        []
                    );

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .manualPull(
                        this.erc20Vault.address,
                        this.yearnVault.address,
                        [usdcAmountForDeposit, wethAmountForDeposit],
                        []
                    );

                const maxAmountForPush = BigNumber.from(2).pow(70).sub(100);
                var pricesHistory: BigNumber[][] = [];

                for (var i = 1; i <= 3; i++) {
                    pricesHistory.push([]);
                    var deltaValue = BigNumber.from(0);
                    for (var j = 1; j <= 10; j++) {
                        const ratioParams: RatioParamsStruct = {
                            tickMin: 198240 - 5000,
                            tickMax: 198240 + 5000,
                            erc20MoneyRatioD: Math.round(j * 0.01 * 10 ** 9),
                            minTickRebalanceThreshold: 0,
                            tickNeighborhood: 0,
                            tickIncrease: 100,
                            minErc20MoneyRatioDeviation0D: Math.round(
                                0.01 * 10 ** 9
                            ),
                            minErc20MoneyRatioDeviation1D: Math.round(
                                0.01 * 10 ** 9
                            ),
                        };

                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .setRatioParams(ratioParams);

                        const currentVault = BigNumber.from(10).pow(12).mul(2);
                        deltaValue = deltaValue.add(
                            currentVault.mul(1000000 + UNIV3_FEE).div(1000000)
                        );

                        await pushPriceDown(currentVault);
                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .rebalance(
                                [BigNumber.from(0), BigNumber.from(0)],
                                []
                            );
                        pricesHistory[i - 1].push(await getSqrtPriceX96());

                        const erc20Tvls = (await this.erc20Vault.tvl())
                            .minTokenAmounts;
                        const yearnTvls = (await this.yearnVault.tvl())
                            .minTokenAmounts;

                        for (var tokenIndex = 0; tokenIndex < 2; tokenIndex++) {
                            const tokenOnErc20 = erc20Tvls[tokenIndex];
                            const tokenOnMoney = yearnTvls[tokenIndex];
                            const expectedPercentOnErc20 = j;
                            const expectedPercentOnMoney = 100 - j;
                            const totalAmount = tokenOnErc20.add(tokenOnMoney);
                            const expectedOnErc20 = totalAmount
                                .mul(expectedPercentOnErc20)
                                .div(100);
                            const expectedOnMoney = totalAmount
                                .mul(expectedPercentOnMoney)
                                .div(100);
                            // token on vault <= expected + 1% of deviation
                            expect(
                                tokenOnErc20.lte(
                                    expectedOnErc20.add(
                                        expectedOnErc20.div(100)
                                    )
                                )
                            );
                            expect(
                                tokenOnMoney.lte(
                                    expectedOnMoney.add(
                                        expectedOnMoney.div(100)
                                    )
                                )
                            );
                        }
                    }

                    deltaValue = deltaValue
                        .mul(await getBestPrice())
                        .div(Common.Q96);

                    while (deltaValue.gt(maxAmountForPush)) {
                        await pushPriceUp(maxAmountForPush);
                        deltaValue = deltaValue.sub(maxAmountForPush);
                    }

                    await pushPriceUp(deltaValue);
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .rebalance([BigNumber.from(0), BigNumber.from(0)], []);
                    pricesHistory[i - 1].push(await getSqrtPriceX96());
                }

                for (var i = 0; i < 2; i++) {
                    for (var j = 0; j < pricesHistory[i].length; j++) {
                        const currentPrice = pricesHistory[i][j];
                        const nextPrice = pricesHistory[i + 1][j];
                        // currentPrice <= nextPrice <= 1.003 * currentPrice
                        expect(currentPrice.lte(nextPrice));
                        expect(
                            currentPrice
                                .mul(1000000 + UNIV3_FEE)
                                .div(1000000)
                                .gte(nextPrice)
                        );
                    }
                }

                return true;
            });
        });

        describe("Multiple price swappings and rebalances with mstrategy with liqidity cycle changing using UniV3Vault", () => {
            it("change liquidity only on fees", async () => {
                await setNonZeroFeesFixture();
                await increasePoolCardinality(BigNumber.from(2000));
                const usdcAmountForDeposit = this.usdcDeployerSupply;
                const wethAmountForDeposit = this.wethDeployerSupply;

                await this.erc20RootVault
                    .connect(this.deployer)
                    .deposit(
                        [usdcAmountForDeposit, wethAmountForDeposit],
                        0,
                        []
                    );

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .manualPull(
                        this.erc20Vault.address,
                        this.yearnVault.address,
                        [usdcAmountForDeposit, wethAmountForDeposit],
                        []
                    );

                const maxAmountForPush = BigNumber.from(2).pow(70).sub(100);
                var pricesHistory: BigNumber[][] = [];

                // if positive - deposit to erc20 and then to UniV3Vault
                // else withdraw

                // wethAmountChanges will be calculated by price functions
                var usdcAmountChanges: BigNumber[] = [];
                const limit = BigNumber.from(10).pow(9);
                var currentBalance = BigNumber.from(0);
                for (var i = 0; i < 9; i++) {
                    var amount = generateRandomBignumber(limit).add(
                        BigNumber.from(10).pow(8)
                    );
                    if (currentBalance.gt(amount.mul(2))) {
                        amount = amount.mul(BigNumber.from(-1));
                    }
                    currentBalance = currentBalance.add(amount);
                    usdcAmountChanges.push(amount);
                }
                currentBalance = currentBalance.mul(BigNumber.from(-1));
                usdcAmountChanges.push(currentBalance);
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.erc20Vault.nft()
                    );
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.yearnVault.nft()
                    );
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.uniV3Vault.nft()
                    );
                for (var i = 1; i <= 3; i++) {
                    pricesHistory.push([]);
                    var deltaValue = BigNumber.from(0);
                    for (var j = 1; j <= 10; j++) {
                        // change liquidity:
                        var currentUsdcChange = usdcAmountChanges[j - 1];
                        var currentWethChange = currentUsdcChange
                            .mul(await getBestPrice())
                            .div(Common.Q96);
                        if (currentUsdcChange.gte(0)) {
                            await mint(
                                "USDC",
                                this.deployer.address,
                                currentUsdcChange
                            );
                            await mint(
                                "WETH",
                                this.deployer.address,
                                currentWethChange
                            );
                            await this.erc20RootVault
                                .connect(this.deployer)
                                .deposit(
                                    [currentUsdcChange, currentWethChange],
                                    BigNumber.from(0),
                                    []
                                );
                            await this.subject
                                .connect(this.mStrategyAdmin)
                                .manualPull(
                                    this.erc20Vault.address,
                                    this.uniV3Vault.address,
                                    [currentUsdcChange, currentWethChange],
                                    []
                                );
                        } else {
                            currentUsdcChange = currentUsdcChange.mul(-1);
                            currentWethChange = currentWethChange.mul(-1);
                            await this.subject
                                .connect(this.mStrategyAdmin)
                                .manualPull(
                                    this.uniV3Vault.address,
                                    this.erc20Vault.address,
                                    [currentUsdcChange, currentWethChange],
                                    []
                                );

                            await this.erc20RootVault
                                .connect(this.deployer)
                                .withdraw(
                                    this.deployer.address,
                                    await getLiquidityByTokenAmounts(
                                        currentUsdcChange,
                                        currentWethChange
                                    ),
                                    [BigNumber.from(0), BigNumber.from(0)],
                                    [[], [], []]
                                );
                        }

                        const currentVault = BigNumber.from(10).pow(12).mul(2);
                        deltaValue = deltaValue.add(
                            currentVault.mul(1000000 + UNIV3_FEE).div(1000000)
                        );
                        await pushPriceDown(currentVault);
                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .rebalance(
                                [BigNumber.from(0), BigNumber.from(0)],
                                []
                            );
                        pricesHistory[i - 1].push(await getSqrtPriceX96());
                    }

                    deltaValue = deltaValue
                        .mul(await getBestPrice())
                        .div(Common.Q96);

                    while (deltaValue.gt(maxAmountForPush)) {
                        await pushPriceUp(maxAmountForPush);
                        deltaValue = deltaValue.sub(maxAmountForPush);
                    }

                    await pushPriceUp(deltaValue);
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .rebalance([BigNumber.from(0), BigNumber.from(0)], []);
                    pricesHistory[i - 1].push(await getSqrtPriceX96());
                }

                for (var i = 0; i < 2; i++) {
                    for (var j = 0; j < pricesHistory[i].length; j++) {
                        const currentPrice = pricesHistory[i][j];
                        const nextPrice = pricesHistory[i + 1][j];
                        // currentPrice <= nextPrice <= 1.003 * currentPrice
                        expect(currentPrice.lte(nextPrice));
                        expect(
                            currentPrice
                                .mul(1000000 + UNIV3_FEE)
                                .div(1000000)
                                .gte(nextPrice)
                        );
                    }
                }

                return true;
            });
        });

        describe("Rebalance distributes tokens in a given ratio", () => {
            it("for every different tickLower, tickUpper and tick given", async () => {
                await setZeroFeesFixture();
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.erc20Vault.nft()
                    );
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.yearnVault.nft()
                    );
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.uniV3Vault.nft()
                    );

                const usdcAmount = BigNumber.from(10).pow(6).mul(3000);
                const wethAmount = BigNumber.from(10).pow(18);
                await mint("USDC", this.deployer.address, usdcAmount);
                await mint("WETH", this.deployer.address, wethAmount);

                await this.erc20RootVault.deposit(
                    [usdcAmount, wethAmount],
                    BigNumber.from(0),
                    []
                );

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .manualPull(
                        this.erc20Vault.address,
                        this.yearnVault.address,
                        [usdcAmount, wethAmount],
                        []
                    );

                const oracleParams: OracleParamsStruct = {
                    oracleObservationDelta: 15,
                    maxTickDeviation: 2 ** 23,
                    maxSlippageD: Math.round(10 ** 9),
                };

                const ratioParams: RatioParamsStruct = {
                    tickMin: 198240 - 5000,
                    tickMax: 198240 + 5000,
                    erc20MoneyRatioD: 0,
                    minTickRebalanceThreshold: 0,
                    tickNeighborhood: 60,
                    tickIncrease: 180,
                    minErc20MoneyRatioDeviation0D: Math.round(0.01 * 10 ** 9),
                    minErc20MoneyRatioDeviation1D: Math.round(0.01 * 10 ** 9),
                };

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .setOracleParams(oracleParams);
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .setRatioParams(ratioParams);

                const getTokens = async () => {
                    const yearnTvls = (await this.yearnVault.tvl())[0];
                    const token0 = yearnTvls[0];
                    const token1 = yearnTvls[1];
                    return {
                        token0,
                        token1,
                    };
                };

                for (var i = 0; i < 10; i++) {
                    const {
                        token0: token0BeforeRebalance,
                        token1: token1BeforeRebalance,
                    } = await getTokens();
                    const { tickMin, tickMax } =
                        await this.subject.ratioParams();
                    const checker = new RebalanceChecker(
                        token0BeforeRebalance,
                        token1BeforeRebalance,
                        tickMin,
                        tickMax,
                        0
                    );

                    const { averageTick: tick } =
                        await this.subject.getAverageTick();
                    try {
                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .rebalance(
                                [BigNumber.from(0), BigNumber.from(0)],
                                []
                            );
                        const { newToken0, newToken1 } =
                            checker.rebalance(tick);

                        const {
                            token0: token0AfterRebalance,
                            token1: token1AfterRebalance,
                        } = await getTokens();

                        expect(
                            newToken0.mul(99).div(100).lte(token0AfterRebalance)
                        );
                        expect(
                            newToken1.mul(99).div(100).lte(token1AfterRebalance)
                        );
                        expect(
                            newToken0
                                .mul(101)
                                .div(100)
                                .gte(token0AfterRebalance)
                        );
                        expect(
                            newToken1
                                .mul(101)
                                .div(100)
                                .gte(token1AfterRebalance)
                        );
                    } catch {
                        // if the ticks have not changed, then do another iteration
                        i--;
                    }

                    const currentTick = await this.subject.getAverageTick();
                    if (Math.random() < 0.5) {
                        do {
                            var delta = generateRandomBignumber(
                                BigNumber.from(10).pow(13)
                            );
                            delta = delta.add(BigNumber.from(10).pow(13));

                            await pushPriceDown(delta);
                        } while (
                            currentTick == (await this.subject.getAverageTick())
                        );
                    } else {
                        do {
                            var delta = generateRandomBignumber(
                                BigNumber.from(10).pow(18)
                            );
                            delta = delta.add(BigNumber.from(10).pow(18));

                            await pushPriceUp(delta);
                        } while (
                            currentTick == (await this.subject.getAverageTick())
                        );
                    }
                }
                return true;
            });
        });

        describe("Rebalance distributes tokens in a given ratio", () => {
            it("for set minTokensAmount", async () => {
                await setZeroFeesFixture();
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.erc20Vault.nft()
                    );
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.yearnVault.nft()
                    );
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.uniV3Vault.nft()
                    );

                const usdcAmount = BigNumber.from(10).pow(6).mul(3000);
                const wethAmount = BigNumber.from(10).pow(18);
                await mint("USDC", this.deployer.address, usdcAmount);
                await mint("WETH", this.deployer.address, wethAmount);

                await this.erc20RootVault.deposit(
                    [usdcAmount, wethAmount],
                    BigNumber.from(0),
                    []
                );

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .manualPull(
                        this.erc20Vault.address,
                        this.yearnVault.address,
                        [usdcAmount, wethAmount],
                        []
                    );

                const oracleParams: OracleParamsStruct = {
                    oracleObservationDelta: 15,
                    maxTickDeviation: 2 ** 23,
                    maxSlippageD: Math.round(10 ** 9),
                };

                const ratioParams: RatioParamsStruct = {
                    tickMin: 198240 - 5000,
                    tickMax: 198240 + 5000,
                    erc20MoneyRatioD: 0,
                    minTickRebalanceThreshold: 0,
                    tickNeighborhood: 60,
                    tickIncrease: 180,
                    minErc20MoneyRatioDeviation0D: Math.round(0.01 * 10 ** 9),
                    minErc20MoneyRatioDeviation1D: Math.round(0.01 * 10 ** 9),
                };

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .setOracleParams(oracleParams);
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .setRatioParams(ratioParams);

                const { tokenAmounts, zeroToOne } = await this.subject
                    .connect(this.mStrategyAdmin)
                    .callStatic.rebalance(
                        [BigNumber.from(0), BigNumber.from(0)],
                        []
                    );

                var minTokensAmount = [BigNumber.from(0), BigNumber.from(0)];
                if (zeroToOne) {
                    minTokensAmount[0] = ethers.constants.MaxUint256;
                    minTokensAmount[1] = tokenAmounts[1];
                } else {
                    minTokensAmount[1] = ethers.constants.MaxUint256;
                    minTokensAmount[0] = tokenAmounts[0];
                }

                // must be processes without any exceptions
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .callStatic.rebalance(
                            minTokensAmount, // minTokensAmount
                            []
                        )
                ).not.to.be.reverted;

                // increase amountOut on 1, to get limit underflow error
                if (zeroToOne) {
                    minTokensAmount[1] = minTokensAmount[1].add(1);
                } else {
                    minTokensAmount[0] = minTokensAmount[0].add(1);
                }

                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .callStatic.rebalance(
                            minTokensAmount, // minTokensAmount
                            []
                        )
                ).to.be.revertedWith(Exceptions.LIMIT_UNDERFLOW);

                return true;
            });
        });
    }
);
