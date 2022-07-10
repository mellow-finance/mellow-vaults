import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Helper,
    UniV3Vault,
    ISwapRouter as SwapRouterInterface,
    IYearnProtocolVault,
    HStrategyHelper,
    IUniswapV3Pool,
} from "./types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    setupVault,
    combineVaults,
    TRANSACTION_GAS_LIMITS,
} from "../deploy/0000_utils";
import { Contract } from "@ethersproject/contracts";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";
import { expect } from "chai";
import { randomInt } from "crypto";
import {
    MockHStrategy,
    StrategyParamsStruct,
    TokenAmountsStruct,
    RatioParamsStruct,
} from "./types/MockHStrategy";
import Exceptions from "./library/Exceptions";
import { LiquidityMath, Tick, TickMath } from "@uniswap/v3-sdk";
import {
    OracleParamsStruct,
    RebalanceRestrictionsStruct,
} from "./types/HStrategy";
import {
    DomainPositionParamsStruct,
    ExpectedRatiosStruct,
    TokenAmountsInToken0Struct,
} from "./types/HStrategyHelper";
import { mapAccumRight } from "ramda";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    uniV3Vault: UniV3Vault;
    uniV3Helper: UniV3Helper;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    params: any;
    deployerWethAmount: BigNumber;
    deployerUsdcAmount: BigNumber;
    swapRouter: SwapRouterInterface;
    hStrategyHelper: HStrategyHelper;
    strategyParams: StrategyParamsStruct;
};

type DeployOptions = {};

const DENOMINATOR = BigNumber.from(10).pow(9);
const Q96 = BigNumber.from(2).pow(96);

contract<MockHStrategy, DeployOptions, CustomContext>("HStrategy", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                const { read } = deployments;
                const { deploy } = deployments;
                const tokens = [this.weth.address, this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();

                /*
                 * Configure & deploy subvaults
                 */
                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;
                let yearnVaultNft = startNft;
                let erc20VaultNft = startNft + 1;
                let uniV3VaultNft = startNft + 2;
                let erc20RootVaultNft = startNft + 3;
                await setupVault(hre, yearnVaultNft, "YearnVaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                await deploy("UniV3Helper", {
                    from: this.deployer.address,
                    contract: "UniV3Helper",
                    args: [],
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS,
                });

                const { address: uniV3Helper } = await ethers.getContract(
                    "UniV3Helper"
                );

                await deploy("HStrategyHelper", {
                    from: this.deployer.address,
                    contract: "HStrategyHelper",
                    args: [],
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS,
                });
                const { address: hStrategyHelper } = await ethers.getContract(
                    "HStrategyHelper"
                );

                this.hStrategyHelper = await ethers.getContractAt(
                    "HStrategyHelper",
                    hStrategyHelper
                );

                await setupVault(hre, uniV3VaultNft, "UniV3VaultGovernance", {
                    createVaultArgs: [
                        tokens,
                        this.deployer.address,
                        3000,
                        uniV3Helper,
                    ],
                });
                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );
                const yearnVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    yearnVaultNft
                );
                const uniV3Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    uniV3VaultNft
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );
                this.yearnVault = await ethers.getContractAt(
                    "YearnVault",
                    yearnVault
                );

                this.uniV3Vault = await ethers.getContractAt(
                    "UniV3Vault",
                    uniV3Vault
                );

                /*
                 * Deploy HStrategy
                 */
                const { uniswapV3PositionManager, uniswapV3Router } =
                    await getNamedAccounts();
                this.positionManager = await ethers.getContractAt(
                    INonfungiblePositionManager,
                    uniswapV3PositionManager
                );
                const hStrategy = await (
                    await ethers.getContractFactory("MockHStrategy")
                ).deploy(uniswapV3PositionManager, uniswapV3Router);
                this.params = {
                    tokens: tokens,
                    erc20Vault: erc20Vault,
                    moneyVault: yearnVault,
                    uniV3Vault: uniV3Vault,
                    fee: 3000,
                    admin: this.mStrategyAdmin.address,
                    uniV3Helper: uniV3Helper,
                    hStrategyHelper: hStrategyHelper,
                };

                const address = await hStrategy.callStatic.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.uniV3Vault,
                    this.params.fee,
                    this.params.admin,
                    this.params.uniV3Helper,
                    this.params.hStrategyHelper
                );
                await hStrategy.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.uniV3Vault,
                    this.params.fee,
                    this.params.admin,
                    this.params.uniV3Helper,
                    this.params.hStrategyHelper
                );
                this.subject = await ethers.getContractAt(
                    "MockHStrategy",
                    address
                );

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

                /*
                 * Configure oracles for the HStrategy
                 */

                const strategyParams = {
                    widthCoefficient: 15,
                    widthTicks: 60,
                    globalLowerTick: 23400,
                    globalUpperTick: 29700,
                    tickNeighborhood: 0,
                    simulateUniV3Interval: false, // simulating uniV2 Interval
                };
                this.strategyParams = strategyParams;

                const oracleParams = {
                    oracleObservationDelta: 150,
                    maxTickDeviation: 100,
                };
                this.oracleParams = oracleParams;

                const ratioParams = {
                    erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5), // 5%
                    minUniV3RatioDeviation0D: BigNumber.from(10).pow(7).mul(5),
                    minUniV3RatioDeviation1D: BigNumber.from(10).pow(7).mul(5),
                    minMoneyRatioDeviation0D: BigNumber.from(10).pow(7).mul(5),
                    minMoneyRatioDeviation1D: BigNumber.from(10).pow(7).mul(5),
                };
                this.ratioParams = ratioParams;

                const mintingParams = {
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                };
                this.mintingParams = mintingParams;

                let txs: string[] = [];
                txs.push(
                    this.subject.interface.encodeFunctionData(
                        "updateStrategyParams",
                        [strategyParams]
                    )
                );
                txs.push(
                    this.subject.interface.encodeFunctionData(
                        "updateOracleParams",
                        [oracleParams]
                    )
                );
                txs.push(
                    this.subject.interface.encodeFunctionData(
                        "updateRatioParams",
                        [ratioParams]
                    )
                );
                txs.push(
                    this.subject.interface.encodeFunctionData(
                        "updateMintingParams",
                        [mintingParams]
                    )
                );
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .functions["multicall"](txs);

                await combineVaults(
                    hre,
                    erc20RootVaultNft,
                    [erc20VaultNft, yearnVaultNft, uniV3VaultNft],
                    this.subject.address,
                    this.deployer.address
                );
                this.erc20RootVaultNft = erc20RootVaultNft;

                const erc20RootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20RootVaultNft
                );
                this.erc20RootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVault
                );

                await this.erc20RootVault
                    .connect(this.admin)
                    .addDepositorsToAllowlist([this.deployer.address]);

                this.deployerUsdcAmount = BigNumber.from(10).pow(9).mul(3000);
                this.deployerWethAmount = BigNumber.from(10).pow(18).mul(4000);

                await mint(
                    "USDC",
                    this.deployer.address,
                    this.deployerUsdcAmount
                );
                await mint(
                    "WETH",
                    this.deployer.address,
                    this.deployerWethAmount
                );

                for (let addr of [
                    this.subject.address,
                    this.erc20RootVault.address,
                ]) {
                    await this.weth.approve(addr, ethers.constants.MaxUint256);
                    await this.usdc.approve(addr, ethers.constants.MaxUint256);
                }

                this.positionManager = await ethers.getContractAt(
                    INonfungiblePositionManager,
                    uniswapV3PositionManager
                );

                this.pool = await ethers.getContractAt(
                    "IUniswapV3Pool",
                    await this.uniV3Vault.pool()
                );

                this.uniV3Helper = await ethers.getContract("UniV3Helper");

                this.mintMockPosition = async () => {
                    const existentials =
                        await this.uniV3Vault.pullExistentials();
                    let { tick } = await this.pool.slot0();
                    tick = BigNumber.from(tick).div(60).mul(60).toNumber();
                    const { tokenId } = await mintUniV3Position_USDC_WETH({
                        tickLower: tick,
                        tickUpper: tick + 60,
                        usdcAmount: existentials[0],
                        wethAmount: existentials[1],
                        fee: 3000,
                    });

                    await this.positionManager.functions[
                        "transferFrom(address,address,uint256)"
                    ](this.deployer.address, this.subject.address, tokenId);
                    await withSigner(this.subject.address, async (signer) => {
                        await this.positionManager
                            .connect(signer)
                            .functions[
                                "safeTransferFrom(address,address,uint256)"
                            ](signer.address, this.uniV3Vault.address, tokenId);
                    });
                };

                this.getPositionParams = async () => {
                    const strategyParams = await this.subject.strategyParams();
                    const oracleParams = await this.subject.oracleParams();
                    const pool = await this.subject.pool();
                    const priceInfo =
                        await this.uniV3Helper.getAverageTickAndSqrtSpotPrice(
                            pool,
                            oracleParams.oracleObservationDelta
                        );
                    return await this.hStrategyHelper.calculateDomainPositionParams(
                        priceInfo.averageTick,
                        priceInfo.sqrtSpotPriceX96,
                        strategyParams,
                        await this.uniV3Vault.uniV3Nft(),
                        this.positionManager.address
                    );
                };

                this.getSqrtRatioAtTick = (tick: number) => {
                    return BigNumber.from(
                        TickMath.getSqrtRatioAtTick(
                            BigNumber.from(tick).toNumber()
                        ).toString()
                    );
                };

                this.tvlToken0 = async () => {
                    const positionParams: DomainPositionParamsStruct =
                        await this.getPositionParams();
                    const averagePriceSqrtX96 = BigNumber.from(
                        positionParams.averagePriceSqrtX96
                    );
                    const price = averagePriceSqrtX96
                        .mul(averagePriceSqrtX96)
                        .div(Q96);
                    const currentAmounts =
                        await this.hStrategyHelper.calculateCurrentTokenAmounts(
                            this.erc20Vault.address,
                            this.yearnVault.address,
                            positionParams
                        );
                    return {
                        erc20Vault: currentAmounts.erc20Token0.add(
                            currentAmounts.erc20Token1.mul(Q96).div(price)
                        ),
                        moneyVault: currentAmounts.moneyToken0.add(
                            currentAmounts.moneyToken1.mul(Q96).div(price)
                        ),
                        uniV3Vault: currentAmounts.uniV3Token0.add(
                            currentAmounts.uniV3Token1.mul(Q96).div(price)
                        ),
                    };
                };

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#constructor", () => {
        it("deploys a new contract", async () => {
            expect(this.subject.address).to.not.eq(
                ethers.constants.AddressZero
            );
        });
    });

    describe("#createStrategy", () => {
        it("creates a new strategy and initializes it", async () => {
            const address = await this.subject
                .connect(this.mStrategyAdmin)
                .callStatic.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.uniV3Vault,
                    this.params.fee,
                    this.params.admin,
                    this.params.uniV3Helper,
                    this.params.hStrategyHelper
                );

            expect(address).to.not.eq(ethers.constants.AddressZero);

            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .createStrategy(
                        this.params.tokens,
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        this.params.uniV3Vault,
                        this.params.fee,
                        this.params.admin,
                        this.params.uniV3Helper,
                        this.params.hStrategyHelper
                    )
            ).to.not.be.reverted;
        });
    });

    describe("#updateParams", () => {
        it("set new strategy parameters", async () => {
            await expect(
                this.subject.connect(this.mStrategyAdmin).updateStrategyParams({
                    ...this.strategyParams,
                } as StrategyParamsStruct)
            ).to.emit(this.subject, "UpdateStrategyParams");
        });

        describe("edge cases:", () => {
            it("when widthCoefficient <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            widthCoefficient: 0,
                        } as StrategyParamsStruct)
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when widthTicks <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            widthTicks: 0,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when oracleObservationDelta <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateOracleParams({
                            ...this.oracleParams,
                            oracleObservationDelta: 0,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when erc20MoneyRatioD <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateRatioParams({
                            ...this.ratioParams,
                            erc20MoneyRatioD: 0,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when erc20MoneyRatioD > DENOMINATOR (1e9), then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateRatioParams({
                            ...this.ratioParams,
                            erc20MoneyRatioD: DENOMINATOR.add(1),
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when minToken0ForOpening <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateMintingParams({
                            ...this.mintingParams,
                            minToken0ForOpening: 0,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when minToken1ForOpening <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateMintingParams({
                            ...this.mintingParams,
                            minToken1ForOpening: 0,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when (2 ^ 22) / widthTicks < widthCoefficient, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            widthCoefficient: BigNumber.from(2).pow(20),
                            widthTicks: BigNumber.from(2).pow(20),
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when globalUpperTick <= globalLowerTick, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            globalLowerTick: 0,
                            globalUpperTick: 0,
                        } as StrategyParamsStruct)
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when widthCoefficient * widthTicks <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            widthCoefficient: 0,
                            widthTicks: 30,
                        } as StrategyParamsStruct)
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when globalIntervalWidth % shortIntervalWidth > 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            widthCoefficient: 1,
                            widthTicks: 30,
                            globalLowerTick: 0,
                            globalUpperTick: 3001,
                        } as StrategyParamsStruct)
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when tickNeighborhood > MAX_TICK, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            tickNeighborhood: TickMath.MAX_TICK + 1,
                        } as StrategyParamsStruct)
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when tickNeighborhood < MIN_TICK, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            tickNeighborhood: TickMath.MIN_TICK - 1,
                        } as StrategyParamsStruct)
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when maxTickDeviation > MAX_TICK, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateOracleParams({
                            ...this.oracleParams,
                            maxTickDeviation: TickMath.MAX_TICK + 1,
                        } as OracleParamsStruct)
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when function called not by strategy admin, then reverts with FORBIDDEN", async () => {
                await expect(
                    this.subject.connect(this.deployer).updateStrategyParams({
                        ...this.strategyParams,
                    } as StrategyParamsStruct)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
        });
    });

    describe("#manualPull", () => {
        it("pulls token amounts from fromVault to toVault", async () => {
            let amountWETH = randomInt(10 ** 4, 10 ** 6);
            let amountUSDC = randomInt(10 ** 4, 10 ** 6);

            await this.usdc
                .connect(this.deployer)
                .transfer(this.erc20Vault.address, amountUSDC);
            await this.weth
                .connect(this.deployer)
                .transfer(this.erc20Vault.address, amountWETH);

            let yTokensAddresses = await this.yearnVault.yTokens();
            let yTokens: IYearnProtocolVault[] = [];
            let yTokenBalances = [];
            for (let i = 0; i < yTokensAddresses.length; ++i) {
                yTokens.push(
                    await ethers.getContractAt(
                        "IYearnProtocolVault",
                        yTokensAddresses[i]
                    )
                );
                yTokenBalances.push(
                    await yTokens[i].balanceOf(this.params.moneyVault)
                );
            }

            for (let i = 0; i < yTokenBalances.length; ++i) {
                expect(yTokenBalances[i]).to.be.eq(0);
            }

            let amountWETHtoPull = randomInt(0, amountWETH);
            let amountUSDCtoPull = randomInt(0, amountUSDC);

            await this.subject
                .connect(this.mStrategyAdmin)
                .manualPull(
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    [amountUSDCtoPull, amountWETHtoPull],
                    []
                );

            for (let i = 0; i < yTokens.length; ++i) {
                yTokenBalances[i] = await yTokens[i].balanceOf(
                    this.params.moneyVault
                );
            }

            for (let i = 0; i < yTokenBalances.length; ++i) {
                expect(yTokenBalances[i]).to.be.gt(0);
            }

            expect(
                await this.weth.balanceOf(this.params.erc20Vault)
            ).to.be.equal(BigNumber.from(amountWETH - amountWETHtoPull));
            expect(
                await this.usdc.balanceOf(this.params.erc20Vault)
            ).to.be.equal(BigNumber.from(amountUSDC - amountUSDCtoPull));

            await this.subject
                .connect(this.mStrategyAdmin)
                .manualPull(
                    this.params.moneyVault,
                    this.params.erc20Vault,
                    [amountUSDCtoPull, amountWETHtoPull],
                    []
                );

            for (let i = 0; i < yTokens.length; ++i) {
                yTokenBalances[i] = await yTokens[i].balanceOf(
                    this.params.moneyVault
                );
            }

            for (let i = 0; i < yTokenBalances.length; ++i) {
                expect(yTokenBalances[i]).to.be.eq(0);
            }

            let usdcBalanceAbsDif = (
                await this.usdc.balanceOf(this.params.erc20Vault)
            )
                .sub(amountUSDC)
                .abs();
            let wethBalanceAbsDif = (
                await this.weth.balanceOf(this.params.erc20Vault)
            )
                .sub(amountWETH)
                .abs();

            expect(
                usdcBalanceAbsDif
                    .mul(10000)
                    .sub(BigNumber.from(amountUSDC))
                    .lte(0)
            ).to.be.true;
            expect(
                wethBalanceAbsDif
                    .mul(10000)
                    .sub(BigNumber.from(amountWETH))
                    .lte(0)
            ).to.be.true;
        });
    });

    const push = async (delta: BigNumber, tokenName: string) => {
        const n = 20;
        var from = "";
        var to = "";
        if (tokenName == "USDC") {
            from = this.usdc.address;
            to = this.weth.address;
        } else {
            from = this.weth.address;
            to = this.usdc.address;
        }

        await mint(tokenName, this.deployer.address, delta);
        for (var i = 0; i < n; i++) {
            await this.swapRouter.exactInputSingle({
                tokenIn: from,
                tokenOut: to,
                fee: 3000,
                recipient: this.deployer.address,
                deadline: ethers.constants.MaxUint256,
                amountIn: delta.div(n),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
            });
        }
    };

    const getAverageTick = async () => {
        return (
            await this.uniV3Helper.getAverageTickAndSqrtSpotPrice(
                await this.subject.pool(),
                30 * 60
            )
        ).averageTick;
    };
    const getSpotTick = async () => {
        var result: number;
        let { tick } = await this.pool.slot0();
        result = tick;
        return result;
    };

    const getSpotPriceX96 = async () => {
        let { sqrtPriceX96 } = await this.pool.slot0();
        return BigNumber.from(sqrtPriceX96).pow(2).div(Q96);
    };

    const getAveragePriceX96 = async () => {
        let tick = await getAverageTick();
        const sqrtPriceX96 = this.getSqrtRatioAtTick(tick);
        return BigNumber.from(sqrtPriceX96).pow(2).div(Q96);
    };

    describe("#rebalance", () => {
        it("performs a rebalance according to strategy params", async () => {
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...this.strategyParams,
                    widthCoefficient: 1,
                    widthTicks: 60,
                    globalLowerTick: -870000,
                    globalUpperTick: 870000,
                    simulateUniV3Interval: true,
                } as StrategyParamsStruct);
            const pullExistentials =
                await this.erc20RootVault.pullExistentials();
            for (var i = 0; i < 2; i++) {
                await this.tokens[i].approve(
                    this.erc20RootVault.address,
                    pullExistentials[i].mul(10)
                );
            }

            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(10)
            );
            await mint(
                "WETH",
                this.subject.address,
                BigNumber.from(10).pow(10)
            );

            // deposit to zero-vault
            await this.erc20RootVault.deposit(
                [pullExistentials[0].mul(10), pullExistentials[1].mul(10)],
                0,
                []
            );

            // normal deposit
            await this.erc20RootVault.deposit(
                [BigNumber.from(10).pow(11), BigNumber.from(10).pow(11)],
                0,
                []
            );

            var restrictions = {
                pulledOnUniV3Vault: [0, 0],
                pulledOnMoneyVault: [0, 0],
                pulledFromUniV3Vault: [0, 0],
                pulledFromMoneyVault: [0, 0],
                swappedAmounts: [0, 0],
                burnedAmounts: [0, 0],
                deadline: ethers.constants.MaxUint256,
            } as RebalanceRestrictionsStruct;

            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            ).not.to.be.reverted;

            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            ).to.be.revertedWith(Exceptions.INVARIANT);

            for (var i = 0; i < 4; i++) {
                await push(BigNumber.from(10).pow(20), "WETH");
                await sleep(this.governanceDelay);
            }

            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            ).to.be.revertedWith(Exceptions.INVARIANT);

            {
                const ratioParams = await this.subject.ratioParams();
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .updateRatioParams({
                        ...ratioParams,
                        minUniV3RatioDeviation0D: 0,
                        minUniV3RatioDeviation1D: 0,
                        minMoneyRatioDeviation0D: 0,
                        minMoneyRatioDeviation1D: 0,
                    } as RatioParamsStruct);
            }

            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            ).not.to.be.reverted;

            for (var i = 0; i < 4; i++) {
                await push(BigNumber.from(10).pow(12), "USDC");
                await sleep(this.governanceDelay);
            }
            await push(BigNumber.from(10).pow(12), "USDC");

            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            ).not.to.be.reverted;

            for (var i = 0; i < 10; i++) {
                await push(BigNumber.from(10).pow(20), "WETH");
                await sleep(this.governanceDelay);
            }

            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            ).not.to.be.reverted;

            const { tickLower, tickUpper } =
                await this.positionManager.callStatic.positions(
                    await this.uniV3Vault.uniV3Nft()
                );

            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...this.strategyParams,
                    widthCoefficient: 1,
                    widthTicks: 60,
                    globalLowerTick: tickLower,
                    globalUpperTick: tickUpper + 60,
                    simulateUniV3Interval: true,
                } as StrategyParamsStruct);

            const pool = await this.subject.pool();

            while (true) {
                let { tick } = await this.pool.slot0();
                if (tick <= tickUpper + 30) {
                    await push(BigNumber.from(10).pow(20), "WETH");
                    await sleep(this.governanceDelay);
                } else {
                    break;
                }
            }
            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            ).not.to.be.reverted;

            while (true) {
                let { tick } = await this.pool.slot0();
                if (tick >= tickLower + 30) {
                    await push(BigNumber.from(10).pow(11), "USDC");
                    await sleep(this.governanceDelay);
                } else {
                    break;
                }
            }
            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            ).not.to.be.reverted;
        });

        const getPriceX96 = (tick: number) => {
            return this.getSqrtRatioAtTick(tick).pow(2).div(Q96);
        };

        it.only("tvl chanages only on fees", async () => {
            const centralTick = await getAverageTick();
            const globalLowerTick = centralTick - 6000 - (centralTick % 600);
            const globalUpperTick = centralTick + 6000 - (centralTick % 600);
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...this.strategyParams,
                    widthCoefficient: 1,
                    widthTicks: 60,
                    globalLowerTick: globalLowerTick,
                    globalUpperTick: globalUpperTick,
                } as StrategyParamsStruct);
            const pullExistentials =
                await this.erc20RootVault.pullExistentials();
            for (var i = 0; i < 2; i++) {
                await this.tokens[i].approve(
                    this.erc20RootVault.address,
                    pullExistentials[i].mul(10)
                );
            }

            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(10)
            );
            await mint(
                "WETH",
                this.subject.address,
                BigNumber.from(10).pow(10)
            );

            // deposit to zero-vault
            await this.erc20RootVault.deposit(
                [pullExistentials[0].mul(10), pullExistentials[1].mul(10)],
                0,
                []
            );

            // normal deposit
            await this.erc20RootVault.deposit(
                [BigNumber.from(10).pow(14), BigNumber.from(10).pow(14)],
                0,
                []
            );

            var restrictions = {
                pulledOnUniV3Vault: [0, 0],
                pulledOnMoneyVault: [0, 0],
                pulledFromUniV3Vault: [0, 0],
                pulledFromMoneyVault: [0, 0],
                swappedAmounts: [0, 0],
                burnedAmounts: [0, 0],
                deadline: ethers.constants.MaxUint256,
            } as RebalanceRestrictionsStruct;

            const ratioParams = await this.subject.ratioParams();
            await this.subject.connect(this.mStrategyAdmin).updateRatioParams({
                ...ratioParams,
                minUniV3RatioDeviation0D: 0,
                minUniV3RatioDeviation1D: 0,
                minMoneyRatioDeviation0D: 0,
                minMoneyRatioDeviation1D: 0,
            } as RatioParamsStruct);
            await sleep(this.governanceDelay);
            const tvlBefore = (await this.erc20RootVault.tvl()).minTokenAmounts;
            var totalCapital = tvlBefore[0].add(
                tvlBefore[1].mul(Q96).div(await getSpotPriceX96())
            );

            await this.erc20RootVaultGovernance
                .connect(this.admin)
                .stageDelayedStrategyParams(this.erc20RootVaultNft, {
                    strategyTreasury: this.erc20Vault.address,
                    strategyPerformanceTreasury: this.erc20Vault.address,
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

            const compare = (x: BigNumber, y: BigNumber, delta: number) => {
                return x
                    .sub(y)
                    .abs()
                    .lte((x.lt(y) ? y : x).mul(delta).div(100));
            };

            const checkState = async () => {
                const erc20Tvl = (await this.erc20Vault.tvl()).minTokenAmounts;
                const moneyTvl = (await this.yearnVault.tvl()).minTokenAmounts;
                const positions = await this.positionManager.positions(
                    await this.uniV3Vault.uniV3Nft()
                );
                const lowerTick = positions.tickLower;
                const upperTick = positions.tickUpper;
                const strategyParams = await this.subject.strategyParams();
                const lower0Tick = strategyParams.globalLowerTick;
                const upper0Tick = strategyParams.globalUpperTick;
                const averageTick = await getAverageTick();
                const averagePriceX96 = getPriceX96(averageTick);
                const erc20MoneyRatioD = (await this.subject.ratioParams())
                    .erc20MoneyRatioD;
                const uniV3Tvl = await this.uniV3Vault.liquidityToTokenAmounts(
                    positions.liquidity
                );
                const sqrtA = this.getSqrtRatioAtTick(lowerTick);
                const sqrtB = this.getSqrtRatioAtTick(upperTick);
                const sqrtA0 = this.getSqrtRatioAtTick(lower0Tick);
                const sqrtB0 = this.getSqrtRatioAtTick(upper0Tick);
                const sqrtC0 = this.getSqrtRatioAtTick(averageTick);

                // devide all by sqrtC0
                const getWxD = () => {
                    const nominatorX96 = Q96.mul(sqrtC0)
                        .div(sqrtB)
                        .sub(Q96.mul(sqrtC0).div(sqrtB0));
                    const denominatorX96 = Q96.mul(2)
                        .sub(Q96.mul(sqrtA0).div(sqrtC0))
                        .sub(Q96.mul(sqrtC0).div(sqrtB0));
                    return nominatorX96.mul(DENOMINATOR).div(denominatorX96);
                };

                const getWyD = () => {
                    const nominatorX96 = Q96.mul(sqrtA)
                        .div(sqrtC0)
                        .sub(Q96.mul(sqrtA0).div(sqrtC0));
                    const denominatorX96 = Q96.mul(2)
                        .sub(Q96.mul(sqrtA0).div(sqrtC0))
                        .sub(Q96.mul(sqrtC0).div(sqrtB0));
                    return nominatorX96.mul(DENOMINATOR).div(denominatorX96);
                };

                const wxD = getWxD();
                const wyD = getWyD();
                const wUniD = DENOMINATOR.sub(wxD).sub(wyD);

                // total tvl:
                const totalToken0 = erc20Tvl[0]
                    .add(moneyTvl[0])
                    .add(uniV3Tvl[0]);
                const totalToken1 = erc20Tvl[1]
                    .add(moneyTvl[1])
                    .add(uniV3Tvl[1]);

                const totalCapital = totalToken0.add(
                    totalToken1.mul(Q96).div(averagePriceX96)
                );

                const xCapital = totalCapital.mul(wxD).div(DENOMINATOR);
                const yCapital = totalCapital
                    .mul(wyD)
                    .div(DENOMINATOR)
                    .mul(averagePriceX96)
                    .div(Q96);

                const uniV3Capital = totalCapital.mul(wUniD).div(DENOMINATOR);

                const expectedErc20Token0 = xCapital
                    .mul(erc20MoneyRatioD)
                    .div(DENOMINATOR);
                const expectedErc20Token1 = yCapital
                    .mul(erc20MoneyRatioD)
                    .div(DENOMINATOR);

                const expectedMoneyToken0 = xCapital.sub(expectedErc20Token0);
                const expectedMoneyToken1 = yCapital.sub(expectedErc20Token1);

                const currentUniV3Capital = uniV3Tvl[0].add(
                    uniV3Tvl[1].mul(Q96).div(averagePriceX96)
                );

                expect(compare(expectedErc20Token0, erc20Tvl[0], 10)).to.be
                    .true;
                expect(compare(expectedErc20Token1, erc20Tvl[1], 10)).to.be
                    .true;
                expect(compare(expectedMoneyToken0, moneyTvl[0], 10)).to.be
                    .true;
                expect(compare(expectedMoneyToken1, moneyTvl[1], 10)).to.be
                    .true;
                expect(compare(uniV3Capital, currentUniV3Capital, 10)).to.be
                    .true;
            };

            const interationsNumber = 10;
            for (var i = 0; i < interationsNumber; i++) {
                console.log("Iteration:", i);
                var doFullRebalance = i == 0 ? true : Math.random() < 0.5;
                if (doFullRebalance) {
                    if (Math.random() < 0.5) {
                        const initialTick = await getSpotTick();
                        var currentTick = initialTick;
                        while (Math.abs(currentTick - initialTick) <= 60) {
                            await push(BigNumber.from(10).pow(13), "USDC");
                            await sleep(this.governanceDelay);
                            currentTick = await getSpotTick();
                        }
                    } else {
                        const initialTick = await getSpotTick();
                        var currentTick = initialTick;
                        while (Math.abs(currentTick - initialTick) <= 60) {
                            await push(BigNumber.from(10).pow(21), "WETH");
                            await sleep(this.governanceDelay);
                            currentTick = await getSpotTick();
                        }
                    }
                } else {
                    if (Math.random() < 0.5) {
                        await push(BigNumber.from(10).pow(10), "USDC");
                        await sleep(this.governanceDelay);
                    } else {
                        await push(BigNumber.from(10).pow(15), "WETH");
                        await sleep(this.governanceDelay);
                    }
                }

                await sleep(this.governanceDelay);
                const token0BalanceBefore = await this.usdc.balanceOf(
                    this.subject.address
                );
                const token1BalanceBefore = await this.weth.balanceOf(
                    this.subject.address
                );
                const spotPriceX96 = await getSpotPriceX96();

                if (doFullRebalance) {
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .rebalance(restrictions, []);
                } else {
                    const spotPrice = await getSpotPriceX96();
                    const averagePrice = await getAveragePriceX96();
                    const nft = await this.uniV3Vault.uniV3Nft();
                    const position = await this.positionManager.positions(nft);
                    const lowerPrice = getPriceX96(position.tickLower);
                    const upperPrice = getPriceX96(position.tickUpper);

                    if (
                        lowerPrice.lte(spotPrice) &&
                        upperPrice.gte(spotPrice) &&
                        lowerPrice.lte(averagePrice) &&
                        upperPrice.gte(averagePrice)
                    ) {
                        console.log("Normal token rebalance");
                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .tokenRebalance(restrictions, []);
                    } else {
                        console.log("Revert by INVARIANT");
                        await expect(
                            this.subject
                                .connect(this.mStrategyAdmin)
                                .tokenRebalance(restrictions, [])
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    }
                }

                const token0BalanceAfter = await this.usdc.balanceOf(
                    this.subject.address
                );
                const token1BalanceAfter = await this.weth.balanceOf(
                    this.subject.address
                );
                totalCapital = totalCapital
                    .add(token0BalanceBefore.sub(token0BalanceAfter))
                    .add(
                        token1BalanceAfter
                            .sub(token1BalanceBefore)
                            .mul(Q96)
                            .div(spotPriceX96)
                    );

                await checkState();
            }
            await this.uniV3Vault.collectEarnings();
            const tvlAfter = (await this.erc20RootVault.tvl()).minTokenAmounts;
            const capitalAfter = tvlAfter[0].add(
                tvlAfter[1].mul(Q96).div(await getSpotPriceX96())
            );

            expect(totalCapital.mul(110).div(100).gte(capitalAfter)).to.be.true;
            expect(capitalAfter.mul(110).div(100).gte(totalCapital)).to.be.true;
        });
    });

    describe("#tokenRebalance", () => {
        it("performs a rebalance according to strategy params", async () => {
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...this.strategyParams,
                    widthCoefficient: 1,
                    widthTicks: 60,
                    globalLowerTick: -870000,
                    globalUpperTick: 870000,
                    simulateUniV3Interval: true,
                } as StrategyParamsStruct);
            const pullExistentials =
                await this.erc20RootVault.pullExistentials();
            for (var i = 0; i < 2; i++) {
                await this.tokens[i].approve(
                    this.erc20RootVault.address,
                    pullExistentials[i].mul(10)
                );
            }

            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(10)
            );
            await mint(
                "WETH",
                this.subject.address,
                BigNumber.from(10).pow(10)
            );

            // deposit to zero-vault
            await this.erc20RootVault.deposit(
                [pullExistentials[0].mul(10), pullExistentials[1].mul(10)],
                0,
                []
            );

            // normal deposit
            await this.erc20RootVault.deposit(
                [BigNumber.from(10).pow(11), BigNumber.from(10).pow(11)],
                0,
                []
            );

            var restrictions = {
                pulledOnUniV3Vault: [0, 0],
                pulledOnMoneyVault: [0, 0],
                pulledFromUniV3Vault: [0, 0],
                pulledFromMoneyVault: [0, 0],
                swappedAmounts: [0, 0],
                burnedAmounts: [0, 0],
                deadline: ethers.constants.MaxUint256,
            } as RebalanceRestrictionsStruct;

            {
                const ratioParams = await this.subject.ratioParams();
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .updateRatioParams({
                        ...ratioParams,
                        minUniV3RatioDeviation0D: 0,
                        minUniV3RatioDeviation1D: 0,
                        minMoneyRatioDeviation0D: 0,
                        minMoneyRatioDeviation1D: 0,
                    } as RatioParamsStruct);
            }

            await this.subject
                .connect(this.mStrategyAdmin)
                .rebalance(restrictions, []);
            await this.erc20RootVault.withdraw(
                ethers.constants.AddressZero,
                10 ** 5,
                [0, 0],
                [[], [], []]
            );
            await this.subject
                .connect(this.mStrategyAdmin)
                .tokenRebalance(restrictions, []);
        });
    });

    describe("calculateExpectedRatios", () => {
        it("correctly calculates the ratio of tokens according to the specification for UniV3 interval simulating", async () => {
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...this.strategyParams,
                } as StrategyParamsStruct);

            for (var i = 0; i < 10; i++) {
                var lower0Tick = randomInt(10000);
                var lowerTick = lower0Tick + randomInt(10000);
                var upperTick = lowerTick + randomInt(10000) + 1;
                var upper0Tick = upperTick + randomInt(10000);
                var averageTick = lowerTick + randomInt(upperTick - lowerTick);

                const lowerPriceSqrtX96 = this.getSqrtRatioAtTick(lowerTick);
                const upperPriceSqrtX96 = this.getSqrtRatioAtTick(upperTick);
                const averagePriceSqrtX96 =
                    this.getSqrtRatioAtTick(averageTick);
                const lower0PriceSqrtX96 = this.getSqrtRatioAtTick(lower0Tick);
                const upper0PriceSqrtX96 = this.getSqrtRatioAtTick(upper0Tick);
                expect(
                    lower0PriceSqrtX96 <= lowerPriceSqrtX96 &&
                        lowerPriceSqrtX96 <= averagePriceSqrtX96 &&
                        averagePriceSqrtX96 <= upperPriceSqrtX96 &&
                        upperPriceSqrtX96 <= upper0PriceSqrtX96
                );
                var strategyParams = this.strategyParams;
                const { token0RatioD, token1RatioD, uniV3RatioD } =
                    await this.hStrategyHelper.callStatic.calculateExpectedRatios(
                        {
                            nft: 0,
                            liquidity: 0,
                            lowerTick: 0,
                            upperTick: 0,
                            lower0Tick: 0,
                            upper0Tick: 0,
                            averageTick: 0,
                            lowerPriceSqrtX96: lowerPriceSqrtX96,
                            upperPriceSqrtX96: upperPriceSqrtX96,
                            lower0PriceSqrtX96: lower0PriceSqrtX96,
                            upper0PriceSqrtX96: upper0PriceSqrtX96,
                            averagePriceSqrtX96: averagePriceSqrtX96,
                            averagePriceX96: 0,
                            spotPriceSqrtX96: 0,
                        } as DomainPositionParamsStruct
                    );

                const averagePriceX96 = averagePriceSqrtX96
                    .mul(averagePriceSqrtX96)
                    .div(Q96);

                const expectedToken0RatioDNominatorD = DENOMINATOR.mul(
                    averagePriceX96
                )
                    .div(upperPriceSqrtX96)
                    .sub(
                        DENOMINATOR.mul(averagePriceX96).div(upper0PriceSqrtX96)
                    );

                const expectedToken1RatioDNominatorD = DENOMINATOR.mul(
                    lowerPriceSqrtX96
                )
                    .sub(DENOMINATOR.mul(lower0PriceSqrtX96))
                    .div(Q96);

                const expectedTokensRatioDDenominatorD = DENOMINATOR.mul(
                    averagePriceSqrtX96.mul(2)
                )
                    .div(Q96)
                    .sub(DENOMINATOR.mul(lower0PriceSqrtX96).div(Q96))
                    .sub(
                        DENOMINATOR.mul(averagePriceX96).div(upper0PriceSqrtX96)
                    );

                const expectedToken0RatioD = DENOMINATOR.mul(
                    expectedToken0RatioDNominatorD
                ).div(expectedTokensRatioDDenominatorD);
                const expectedToken1RatioD = DENOMINATOR.mul(
                    expectedToken1RatioDNominatorD
                ).div(expectedTokensRatioDDenominatorD);

                expect(token0RatioD + token1RatioD + uniV3RatioD).to.be.eq(
                    DENOMINATOR.toNumber()
                );
                expect(expectedToken0RatioD.sub(token0RatioD).abs()).lte(
                    expectedToken0RatioD.div(10000)
                );
                expect(expectedToken1RatioD.sub(token1RatioD).abs()).lte(
                    expectedToken1RatioD.div(10000)
                );
            }
        });
    });

    describe("calculateDomainPositionParams", () => {
        it("correctly calculates parameters of global and short intervals for given position and strategy parameters", async () => {
            for (var i = 0; i < 3; i++) {
                const lowerTick = 0;
                const upperTick = 60 * 10 * 12;

                const averageTick =
                    lowerTick + randomInt(upperTick - lowerTick);

                const { tokenId } = await mintUniV3Position_USDC_WETH({
                    fee: 3000,
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    usdcAmount: this.deployerUsdcAmount,
                    wethAmount: this.deployerWethAmount,
                });

                const globalUpperTick = upperTick + randomInt(10);
                const globalLowerTick = lowerTick - randomInt(100);

                const strategyParams = {
                    ...this.strategyParams,
                    globalLowerTick: globalLowerTick,
                    globalUpperTick: globalUpperTick,
                } as StrategyParamsStruct;

                const result =
                    await this.hStrategyHelper.calculateDomainPositionParams(
                        averageTick,
                        this.getSqrtRatioAtTick(averageTick),
                        strategyParams,
                        tokenId,
                        this.positionManager.address
                    );

                expect(result.lower0Tick).to.be.eq(globalLowerTick);
                expect(result.upper0Tick).to.be.eq(globalUpperTick);

                expect(result.lowerTick).to.be.eq(lowerTick);
                expect(result.upperTick).to.be.eq(upperTick);

                expect(result.lower0PriceSqrtX96).to.be.eq(
                    this.getSqrtRatioAtTick(globalLowerTick)
                );
                expect(result.upper0PriceSqrtX96).to.be.eq(
                    this.getSqrtRatioAtTick(globalUpperTick)
                );

                expect(result.lowerPriceSqrtX96).to.be.eq(
                    this.getSqrtRatioAtTick(lowerTick)
                );
                expect(result.upperPriceSqrtX96).to.be.eq(
                    this.getSqrtRatioAtTick(upperTick)
                );

                expect(result.liquidity).to.be.gt(0);
                expect(result.nft).to.be.eq(tokenId);
                expect(result.averageTick).to.be.eq(averageTick);

                const priceSqrtX96 = this.getSqrtRatioAtTick(averageTick);
                expect(result.averagePriceSqrtX96).to.be.eq(priceSqrtX96);
                const priceX96 = priceSqrtX96.mul(priceSqrtX96).div(Q96);

                expect(result.averagePriceX96).to.be.eq(priceX96);
                expect(result.spotPriceSqrtX96).to.be.eq(priceSqrtX96);
            }
        });
    });

    describe("calculateExpectedTokenAmountsInToken0", () => {
        it("correctly calculates expected token amonuts in token 0", async () => {
            for (var i = 0; i < 3; i++) {
                var tokenAmounts = {
                    erc20TokensAmountInToken0: randomInt(10 ** 9),
                    moneyTokensAmountInToken0: randomInt(10 ** 9),
                    uniV3TokensAmountInToken0: randomInt(10 ** 9),
                    totalTokensInToken0: 0,
                } as TokenAmountsInToken0Struct;
                tokenAmounts.totalTokensInToken0 = BigNumber.from(
                    tokenAmounts.erc20TokensAmountInToken0
                )
                    .add(tokenAmounts.moneyTokensAmountInToken0)
                    .add(tokenAmounts.uniV3TokensAmountInToken0);

                var ratios = {
                    token0RatioD: randomInt(10 ** 8) * 4,
                    token1RatioD: randomInt(10 ** 8) * 4,
                    uniV3RatioD: 0,
                } as ExpectedRatiosStruct;
                ratios.uniV3RatioD = BigNumber.from(ratios.token0RatioD).add(
                    ratios.token1RatioD
                );

                const ratioParams = {
                    ...this.ratioParams,
                    erc20MoneyRatioD: BigNumber.from(10)
                        .pow(7)
                        .mul(randomInt(100)),
                };

                const {
                    erc20TokensAmountInToken0,
                    uniV3TokensAmountInToken0,
                    moneyTokensAmountInToken0,
                    totalTokensInToken0,
                } = await this.hStrategyHelper.calculateExpectedTokenAmountsInToken0(
                    tokenAmounts,
                    ratios,
                    ratioParams
                );

                expect(totalTokensInToken0).to.be.eq(
                    tokenAmounts.totalTokensInToken0
                );
                expect(uniV3TokensAmountInToken0).to.be.eq(
                    totalTokensInToken0.mul(ratios.uniV3RatioD).div(DENOMINATOR)
                );

                const realRatio = erc20TokensAmountInToken0
                    .mul(DENOMINATOR)
                    .div(
                        moneyTokensAmountInToken0.add(erc20TokensAmountInToken0)
                    );

                expect(realRatio).to.be.lte(
                    ratioParams.erc20MoneyRatioD.add(10)
                );
                expect(realRatio).to.be.gte(
                    ratioParams.erc20MoneyRatioD.sub(10)
                );
            }
        });
    });

    describe("calculateCurrentTokenAmountsInToken0", () => {
        it("correctly calculates current token amonuts in token 0", async () => {
            for (var i = 0; i < 3; i++) {
                const domainParams = {
                    nft: 0,
                    liquidity: 0,
                    lowerTick: 0,
                    upperTick: 0,
                    lower0Tick: 0,
                    upper0Tick: 0,
                    averageTick: 0,
                    lowerPriceSqrtX96: 0,
                    upperPriceSqrtX96: 0,
                    lower0PriceSqrtX96: 0,
                    upper0PriceSqrtX96: 0,
                    averagePriceSqrtX96: 0,
                    averagePriceX96: BigNumber.from(10)
                        .pow(9)
                        .mul(Q96.div(1000)),
                    spotPriceSqrtX96: 0,
                } as DomainPositionParamsStruct;

                const amounts = {
                    erc20Token0: randomInt(10 ** 9),
                    erc20Token1: randomInt(10 ** 9),
                    uniV3Token0: randomInt(10 ** 9),
                    uniV3Token1: randomInt(10 ** 9),
                    moneyToken0: randomInt(10 ** 9),
                    moneyToken1: randomInt(10 ** 9),
                } as TokenAmountsStruct;

                const {
                    erc20TokensAmountInToken0,
                    moneyTokensAmountInToken0,
                    uniV3TokensAmountInToken0,
                    totalTokensInToken0,
                } = await this.hStrategyHelper.calculateCurrentTokenAmountsInToken0(
                    domainParams,
                    amounts
                );

                const convert = (t0: string, t1: string) => {
                    return BigNumber.from(t0).add(
                        BigNumber.from(t1)
                            .mul(Q96)
                            .div(domainParams.averagePriceX96)
                    );
                };

                expect(erc20TokensAmountInToken0).to.be.eq(
                    convert(
                        amounts.erc20Token0.toString(),
                        amounts.erc20Token1.toString()
                    )
                );
                expect(moneyTokensAmountInToken0).to.be.eq(
                    convert(
                        amounts.moneyToken0.toString(),
                        amounts.moneyToken1.toString()
                    )
                );
                expect(uniV3TokensAmountInToken0).to.be.eq(
                    convert(
                        amounts.uniV3Token0.toString(),
                        amounts.uniV3Token1.toString()
                    )
                );

                expect(
                    erc20TokensAmountInToken0
                        .add(moneyTokensAmountInToken0)
                        .add(uniV3TokensAmountInToken0)
                ).to.be.eq(totalTokensInToken0);
            }
        });
    });

    describe("#calculateCurrentTokenAmounts", () => {
        beforeEach(async () => {
            await this.mintMockPosition();
            const { nft } = await this.getPositionParams();
            const { tickLower, tickUpper } =
                await this.positionManager.positions(nft);
            const strategyParams = await this.subject.strategyParams();
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...strategyParams,
                    globalLowerTick: tickLower - 600,
                    globalUpperTick: tickUpper + 600,
                    widthCoefficient: 1,
                    widthTicks: 60,
                });
        });
        describe("initial zero", () => {
            it("equals zero", async () => {
                const positionParams = await this.getPositionParams();
                const result =
                    await this.hStrategyHelper.calculateCurrentTokenAmounts(
                        this.erc20Vault.address,
                        this.yearnVault.address,
                        positionParams
                    );
                expect(result.erc20Token0.toNumber()).to.be.eq(0);
                expect(result.erc20Token1.toNumber()).to.be.eq(0);
                expect(result.moneyToken0.toNumber()).to.be.eq(0);
                expect(result.moneyToken1.toNumber()).to.be.eq(0);
                expect(result.uniV3Token0.gt(0) || result.uniV3Token1.gt(0)).to
                    .be.true;
                const pullExistentials =
                    await this.uniV3Vault.pullExistentials();
                expect(result.uniV3Token0.lte(pullExistentials[0])).to.be.true;
                expect(result.uniV3Token1.lte(pullExistentials[1])).to.be.true;
            });
        });

        describe("erc20 vault", () => {
            it("works", async () => {
                const positionParams = await this.getPositionParams();
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6)
                );
                {
                    const { erc20Token0, erc20Token1 } =
                        await this.hStrategyHelper.calculateCurrentTokenAmounts(
                            this.erc20Vault.address,
                            this.yearnVault.address,
                            positionParams
                        );
                    expect(
                        erc20Token0.sub(BigNumber.from(10).pow(6)).toNumber()
                    ).to.be.eq(0);
                    expect(
                        erc20Token1.sub(BigNumber.from(10).pow(18)).toNumber()
                    ).to.be.eq(0);
                }
                await withSigner(this.erc20Vault.address, async (signer) => {
                    await this.weth
                        .connect(signer)
                        .transfer(
                            randomAddress(),
                            BigNumber.from(10).pow(18).div(2)
                        );
                    await this.usdc
                        .connect(signer)
                        .transfer(
                            randomAddress(),
                            BigNumber.from(10).pow(6).div(2)
                        );
                });
                {
                    const { erc20Token0, erc20Token1 } =
                        await this.hStrategyHelper.calculateCurrentTokenAmounts(
                            this.erc20Vault.address,
                            this.yearnVault.address,
                            positionParams
                        );
                    expect(
                        erc20Token0
                            .sub(BigNumber.from(10).pow(6).div(2))
                            .toNumber()
                    ).to.be.eq(0);
                    expect(
                        erc20Token1
                            .sub(BigNumber.from(10).pow(18).div(2))
                            .toNumber()
                    ).to.be.eq(0);
                }
            });
        });

        describe("money vault", () => {
            it("works", async () => {
                const positionParams = await this.getPositionParams();
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6)
                );
                await withSigner(this.subject.address, async (signer) => {
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.yearnVault.address,
                            [this.usdc.address, this.weth.address],
                            [
                                BigNumber.from(10).pow(6),
                                BigNumber.from(10).pow(18),
                            ],
                            []
                        );
                });
                {
                    const { moneyToken0, moneyToken1 } =
                        await this.hStrategyHelper.calculateCurrentTokenAmounts(
                            this.erc20Vault.address,
                            this.yearnVault.address,
                            positionParams
                        );
                    expect(
                        moneyToken0
                            .sub(BigNumber.from(10).pow(6))
                            .abs()
                            .toNumber()
                    ).to.be.lte(10);
                    expect(
                        moneyToken1
                            .sub(BigNumber.from(10).pow(18))
                            .abs()
                            .toNumber()
                    ).to.be.lte(10);
                }
                await withSigner(this.subject.address, async (signer) => {
                    await this.yearnVault
                        .connect(signer)
                        .pull(
                            this.erc20Vault.address,
                            [this.usdc.address, this.weth.address],
                            [
                                ethers.constants.MaxUint256,
                                ethers.constants.MaxUint256,
                            ],
                            []
                        );
                });
                {
                    const { moneyToken0, moneyToken1 } =
                        await this.hStrategyHelper.calculateCurrentTokenAmounts(
                            this.erc20Vault.address,
                            this.yearnVault.address,
                            positionParams
                        );
                    expect(moneyToken0.toNumber()).to.be.eq(0);
                    expect(moneyToken1.toNumber()).to.be.eq(0);
                }
            });
        });

        describe("uni v3 vault", () => {
            it("works", async () => {
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6).mul(2000)
                );
                await withSigner(this.subject.address, async (signer) => {
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.uniV3Vault.address,
                            [this.usdc.address, this.weth.address],
                            [
                                BigNumber.from(10).pow(6).mul(2000),
                                BigNumber.from(10).pow(18),
                            ],
                            []
                        );
                });

                {
                    const positionParams = await this.getPositionParams();
                    const requiedAmounts =
                        await this.uniV3Helper.liquidityToTokenAmounts(
                            positionParams.liquidity,
                            this.pool.address,
                            await this.uniV3Vault.uniV3Nft(),
                            this.positionManager.address
                        );
                    const { uniV3Token0, uniV3Token1 } =
                        await await this.hStrategyHelper.calculateCurrentTokenAmounts(
                            this.erc20Vault.address,
                            this.yearnVault.address,
                            positionParams
                        );
                    expect(
                        uniV3Token0.sub(requiedAmounts[0]).abs().toNumber()
                    ).to.be.lte(10);
                    expect(
                        uniV3Token1.sub(requiedAmounts[1]).abs().toNumber()
                    ).to.be.lte(10);
                }

                await withSigner(this.subject.address, async (signer) => {
                    await this.uniV3Vault
                        .connect(signer)
                        .pull(
                            this.erc20Vault.address,
                            [this.usdc.address, this.weth.address],
                            [Q96, Q96],
                            []
                        );
                });

                {
                    const positionParams = await this.getPositionParams();
                    const { uniV3Token0, uniV3Token1 } =
                        await this.hStrategyHelper.calculateCurrentTokenAmounts(
                            this.erc20Vault.address,
                            this.yearnVault.address,
                            positionParams
                        );
                    expect(uniV3Token0.toNumber()).to.be.eq(0);
                    expect(uniV3Token1.toNumber()).to.be.eq(0);
                }
            });
        });
    });

    describe("calculateExpectedTokenAmounts", () => {
        beforeEach(async () => {
            await this.mintMockPosition();
            const { nft } = await this.getPositionParams();
            const { tickLower, tickUpper } =
                await this.positionManager.positions(nft);
            const strategyParams = await this.subject.strategyParams();
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...strategyParams,
                    globalLowerTick: tickLower - 600,
                    globalUpperTick: tickUpper + 600,
                    widthCoefficient: 1,
                    widthTicks: 60,
                });
        });

        const actualExpectedTokenAmounts = async (
            ratioParams: RatioParamsStruct
        ) => {
            const positionParams = await this.getPositionParams();
            const ratios = await this.hStrategyHelper.calculateExpectedRatios(
                positionParams
            );
            const currentAmounts =
                await this.hStrategyHelper.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    positionParams
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.calculateCurrentTokenAmountsInToken0(
                    positionParams,
                    currentAmounts
                );
            const expectedInToken0 =
                await this.hStrategyHelper.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    ratioParams
                );
            return await this.hStrategyHelper.calculateExpectedTokenAmounts(
                ratios,
                expectedInToken0,
                positionParams
            );
        };

        const requiredExpectedTokenAmounts = async (
            ratioParams: RatioParamsStruct
        ) => {
            const positionParams = await this.getPositionParams();
            const ratios = await this.hStrategyHelper.calculateExpectedRatios(
                positionParams
            );
            const currentAmounts =
                await this.hStrategyHelper.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    positionParams
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.calculateCurrentTokenAmountsInToken0(
                    positionParams,
                    currentAmounts
                );
            const expectedInToken0 =
                await this.hStrategyHelper.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    ratioParams
                );
            const erc20Token0 = expectedInToken0.erc20TokensAmountInToken0
                .mul(ratios.token0RatioD)
                .div(ratios.token0RatioD + ratios.token1RatioD);
            const erc20Token1 = expectedInToken0.erc20TokensAmountInToken0
                .sub(erc20Token0)
                .mul(positionParams.averagePriceX96)
                .div(Q96);
            const moneyToken0 = expectedInToken0.moneyTokensAmountInToken0
                .mul(ratios.token0RatioD)
                .div(ratios.token0RatioD + ratios.token1RatioD);
            const moneyToken1 = expectedInToken0.moneyTokensAmountInToken0
                .sub(moneyToken0)
                .mul(positionParams.averagePriceX96)
                .div(Q96);
            const uniV3RatioX96 = positionParams.spotPriceSqrtX96
                .sub(positionParams.lowerPriceSqrtX96)
                .mul(Q96)
                .div(
                    positionParams.upperPriceSqrtX96.sub(
                        positionParams.spotPriceSqrtX96
                    )
                )
                .mul(positionParams.upperPriceSqrtX96)
                .div(positionParams.spotPriceSqrtX96);
            const uni1Capital = expectedInToken0.uniV3TokensAmountInToken0
                .mul(uniV3RatioX96)
                .div(uniV3RatioX96.add(Q96));
            const uniV3Token0 =
                expectedInToken0.uniV3TokensAmountInToken0.sub(uni1Capital);
            const spotPriceX96 = positionParams.spotPriceSqrtX96
                .mul(positionParams.spotPriceSqrtX96)
                .div(Q96);
            const uniV3Token1 = uni1Capital.mul(spotPriceX96).div(Q96);
            return {
                erc20Token0,
                erc20Token1,
                moneyToken0,
                moneyToken1,
                uniV3Token0,
                uniV3Token1,
            } as TokenAmountsStruct;
        };

        const compareExpectedAmounts = async () => {
            const ratioParams = await this.subject.ratioParams();
            const required = await requiredExpectedTokenAmounts(ratioParams);
            const actual = await actualExpectedTokenAmounts(ratioParams);
            expect(
                BigNumber.from(required.erc20Token0)
                    .sub(actual.erc20Token0)
                    .toNumber()
            ).to.be.eq(0);
            expect(
                BigNumber.from(required.erc20Token1)
                    .sub(actual.erc20Token1)
                    .toNumber()
            ).to.be.eq(0);
            expect(
                BigNumber.from(required.moneyToken0)
                    .sub(actual.moneyToken0)
                    .toNumber()
            ).to.be.eq(0);
            expect(
                BigNumber.from(required.moneyToken1)
                    .sub(actual.moneyToken1)
                    .toNumber()
            ).to.be.eq(0);
            expect(
                BigNumber.from(required.uniV3Token0)
                    .sub(actual.uniV3Token0)
                    .toNumber()
            ).to.be.eq(0);
            expect(
                BigNumber.from(required.uniV3Token1)
                    .sub(actual.uniV3Token1)
                    .toNumber()
            ).to.be.eq(0);
        };

        describe("simple test", () => {
            it("works", async () => {
                await compareExpectedAmounts();
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6).mul(2000)
                );
                await compareExpectedAmounts();
                await withSigner(this.subject.address, async (signer) => {
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.uniV3Vault.address,
                            [this.usdc.address, this.weth.address],
                            [Q96, Q96],
                            []
                        );
                });
                await compareExpectedAmounts();
            });
        });

        const compareCurrentAndExpected = async () => {
            const positionParams = await this.getPositionParams();
            const ratioParams = await this.subject.ratioParams();
            const expected = await actualExpectedTokenAmounts(ratioParams);
            const totalCapital0 = expected.erc20Token0
                .add(expected.moneyToken0)
                .add(expected.uniV3Token0);
            const priceX96 = positionParams.averagePriceX96;
            const spotPriceX96 = positionParams.spotPriceSqrtX96
                .mul(positionParams.spotPriceSqrtX96)
                .div(Q96);
            const totalCapital1 = expected.erc20Token1
                .add(expected.moneyToken1)
                .mul(Q96)
                .div(priceX96)
                .add(expected.uniV3Token1.mul(Q96).div(spotPriceX96));
            const totalCapitalExpected = totalCapital0.add(totalCapital1);
            const currentAmountsInToken0 =
                await this.hStrategyHelper.calculateCurrentTokenAmountsInToken0(
                    await this.getPositionParams(),
                    await this.hStrategyHelper.calculateCurrentTokenAmounts(
                        this.erc20Vault.address,
                        this.yearnVault.address,
                        positionParams
                    )
                );
            const currentCapital =
                currentAmountsInToken0.erc20TokensAmountInToken0
                    .add(currentAmountsInToken0.moneyTokensAmountInToken0)
                    .add(currentAmountsInToken0.uniV3TokensAmountInToken0);
            const absDiff = currentCapital.sub(totalCapitalExpected).abs();
            expect(absDiff.mul(100).lte(currentCapital)).to.be.true;
        };

        describe("capital is not changed", () => {
            it("is equal to current", async () => {
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6).mul(2000)
                );
                await compareCurrentAndExpected();
                await withSigner(this.subject.address, async (signer) => {
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.uniV3Vault.address,
                            [this.usdc.address, this.weth.address],
                            [Q96, Q96],
                            []
                        );
                });
                await compareCurrentAndExpected();
            });
        });
    });

    describe("calculateExtraTokenAmountsForMoneyVault", () => {
        beforeEach(async () => {
            await this.mintMockPosition();
            const { nft } = await this.getPositionParams();
            const { tickLower, tickUpper } =
                await this.positionManager.positions(nft);
            const strategyParams = await this.subject.strategyParams();
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...strategyParams,
                    globalLowerTick: tickLower - 600,
                    globalUpperTick: tickUpper + 600,
                    widthCoefficient: 1,
                    widthTicks: 60,
                });
        });

        const checkExtraAmounts = async () => {
            const ratioParams = await this.subject.ratioParams();
            const position = await this.getPositionParams();
            const currentAmounts =
                await this.hStrategyHelper.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    position
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.calculateCurrentTokenAmountsInToken0(
                    position,
                    currentAmounts
                );
            const ratios = await this.hStrategyHelper.calculateExpectedRatios(
                position
            );
            const amountsInToken0 =
                await this.hStrategyHelper.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    ratioParams
                );
            const expectedAmounts =
                await this.hStrategyHelper.calculateExpectedTokenAmounts(
                    ratios,
                    amountsInToken0,
                    position
                );
            const actualExtraAmounts =
                await this.hStrategyHelper.calculateExtraTokenAmountsForMoneyVault(
                    this.yearnVault.address,
                    expectedAmounts
                );
            const requiredExtraAmounts = {
                token0Amount: expectedAmounts.moneyToken0.lte(
                    currentAmounts.moneyToken0
                )
                    ? currentAmounts.moneyToken0.sub(
                          expectedAmounts.moneyToken0
                      )
                    : BigNumber.from(0),
                token1Amount: expectedAmounts.moneyToken1.lte(
                    currentAmounts.moneyToken1
                )
                    ? currentAmounts.moneyToken1.sub(
                          expectedAmounts.moneyToken1
                      )
                    : BigNumber.from(0),
            };
            expect(
                requiredExtraAmounts.token0Amount
                    .sub(actualExtraAmounts.token0Amount)
                    .toNumber()
            ).to.be.eq(0);
            expect(
                requiredExtraAmounts.token1Amount
                    .sub(actualExtraAmounts.token1Amount)
                    .toNumber()
            ).to.be.eq(0);
        };

        describe("simple test", () => {
            it("works", async () => {
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6).mul(2000)
                );
                await checkExtraAmounts();
                await withSigner(this.subject.address, async (signer) => {
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.uniV3Vault.address,
                            [this.usdc.address, this.weth.address],
                            [Q96, Q96],
                            []
                        );
                });
                await checkExtraAmounts();
            });
        });
    });

    describe("calculateMissingTokenAmounts", () => {
        beforeEach(async () => {
            await this.mintMockPosition();
            const { nft } = await this.getPositionParams();
            const { tickLower, tickUpper } =
                await this.positionManager.positions(nft);
            const strategyParams = await this.subject.strategyParams();
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...strategyParams,
                    globalLowerTick: tickLower - 600,
                    globalUpperTick: tickUpper + 600,
                    widthCoefficient: 1,
                    widthTicks: 60,
                });
        });

        const checkMissingAmounts = async () => {
            const ratioParams = await this.subject.ratioParams();
            const position = await this.getPositionParams();
            const currentAmounts =
                await this.hStrategyHelper.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    position
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.calculateCurrentTokenAmountsInToken0(
                    position,
                    currentAmounts
                );
            const ratios = await this.hStrategyHelper.calculateExpectedRatios(
                position
            );
            const amountsInToken0 =
                await this.hStrategyHelper.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    ratioParams
                );
            const expectedAmounts =
                await this.hStrategyHelper.calculateExpectedTokenAmounts(
                    ratios,
                    amountsInToken0,
                    position
                );
            const actualMissingAmounts =
                await this.hStrategyHelper.calculateMissingTokenAmounts(
                    this.yearnVault.address,
                    expectedAmounts,
                    position
                );
            const requiredMissingAmounts = {
                moneyToken0: expectedAmounts.moneyToken0.gte(
                    currentAmounts.moneyToken0
                )
                    ? expectedAmounts.moneyToken0.sub(
                          currentAmounts.moneyToken0
                      )
                    : BigNumber.from(0),
                moneyToken1: expectedAmounts.moneyToken1.gte(
                    currentAmounts.moneyToken1
                )
                    ? expectedAmounts.moneyToken1.sub(
                          currentAmounts.moneyToken1
                      )
                    : BigNumber.from(0),
                uniV3Token0: expectedAmounts.uniV3Token0.gte(
                    currentAmounts.uniV3Token0
                )
                    ? expectedAmounts.uniV3Token0.sub(
                          currentAmounts.uniV3Token0
                      )
                    : BigNumber.from(0),
                uniV3Token1: expectedAmounts.uniV3Token1.gte(
                    currentAmounts.uniV3Token1
                )
                    ? expectedAmounts.uniV3Token1.sub(
                          currentAmounts.uniV3Token1
                      )
                    : BigNumber.from(0),
            };
            expect(
                actualMissingAmounts.moneyToken0
                    .sub(requiredMissingAmounts.moneyToken0)
                    .toNumber()
            ).to.be.eq(0);
            expect(
                actualMissingAmounts.moneyToken1
                    .sub(requiredMissingAmounts.moneyToken1)
                    .toNumber()
            ).to.be.eq(0);
            expect(
                actualMissingAmounts.uniV3Token0
                    .sub(requiredMissingAmounts.uniV3Token0)
                    .toNumber()
            ).to.be.eq(0);
            expect(
                actualMissingAmounts.uniV3Token1
                    .sub(requiredMissingAmounts.uniV3Token1)
                    .toNumber()
            ).to.be.eq(0);
        };

        describe("simple test", () => {
            it("works", async () => {
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6).mul(2000)
                );
                await checkMissingAmounts();
                await withSigner(this.subject.address, async (signer) => {
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.uniV3Vault.address,
                            [this.usdc.address, this.weth.address],
                            [Q96, Q96],
                            []
                        );
                });
                await checkMissingAmounts();
            });
        });
    });

    describe("swapTokens", () => {
        beforeEach(async () => {
            await this.mintMockPosition();
            const { nft } = await this.getPositionParams();
            const { tickLower, tickUpper } =
                await this.positionManager.positions(nft);
            const strategyParams = await this.subject.strategyParams();
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...strategyParams,
                    globalLowerTick: tickLower - 600,
                    globalUpperTick: tickUpper + 600,
                    widthCoefficient: 1,
                    widthTicks: 60,
                });
            await this.weth.transfer(
                this.erc20Vault.address,
                BigNumber.from(10).pow(18)
            );
            await this.usdc.transfer(
                this.erc20Vault.address,
                BigNumber.from(10).pow(6)
            );
        });

        const getSwapParams = async () => {
            const ratioParams = await this.subject.ratioParams();
            const position = await this.getPositionParams();
            const currentAmounts =
                await this.hStrategyHelper.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    position
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.calculateCurrentTokenAmountsInToken0(
                    position,
                    currentAmounts
                );
            const ratios = await this.hStrategyHelper.calculateExpectedRatios(
                position
            );
            const amountsInToken0 =
                await this.hStrategyHelper.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    ratioParams
                );
            const expectedAmounts =
                await this.hStrategyHelper.calculateExpectedTokenAmounts(
                    ratios,
                    amountsInToken0,
                    position
                );
            return { currentAmounts, expectedAmounts };
        };

        describe("emits event", () => {
            it("emits", async () => {
                const { currentAmounts, expectedAmounts } =
                    await getSwapParams();
                await expect(
                    this.subject.swapTokens(expectedAmounts, currentAmounts, {
                        pulledOnUniV3Vault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        pulledOnMoneyVault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        pulledFromMoneyVault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        pulledFromUniV3Vault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        swappedAmounts: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        burnedAmounts: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        deadline: ethers.constants.MaxUint256,
                    })
                ).to.emit(this.subject, "SwapTokensOnERC20Vault");
            });
        });

        describe("fails on not enough swap", () => {
            it("reverts", async () => {
                const { currentAmounts, expectedAmounts } =
                    await getSwapParams();
                await expect(
                    this.subject.swapTokens(expectedAmounts, currentAmounts, {
                        pulledOnUniV3Vault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        pulledOnMoneyVault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        pulledFromMoneyVault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        pulledFromUniV3Vault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        swappedAmounts: [
                            ethers.constants.MaxUint256,
                            ethers.constants.MaxUint256,
                        ],
                        burnedAmounts: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        deadline: ethers.constants.MaxUint256,
                    })
                ).to.be.revertedWith(Exceptions.LIMIT_UNDERFLOW);
            });
        });
    });

    ContractMetaBehaviour.call(this, {
        contractName: "HStrategy",
        contractVersion: "1.0.0",
    });
});
