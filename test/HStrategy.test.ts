import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint } from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Helper,
    UniV3Vault,
    IYearnProtocolVault,
} from "./types";
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
    DomainPositionParamsStruct,
} from "./types/MockHStrategy";
import Exceptions from "./library/Exceptions";
import { TickMath } from "@uniswap/v3-sdk";

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
};

type DeployOptions = {};

const DENOMINATOR = BigNumber.from(10).pow(9);

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
                };

                const address = await hStrategy.callStatic.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.uniV3Vault,
                    this.params.fee,
                    this.params.admin,
                    this.params.uniV3Helper
                );
                await hStrategy.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.uniV3Vault,
                    this.params.fee,
                    this.params.admin,
                    this.params.uniV3Helper
                );
                this.subject = await ethers.getContractAt(
                    "MockHStrategy",
                    address
                );

                /*
                 * Configure oracles for the HStrategy
                 */

                const startegyParams = {
                    widthCoefficient: 15,
                    widthTicks: 60,
                    oracleObservationDelta: 150,
                    erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5), // 5%
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    globalLowerTick: 23400,
                    globalUpperTick: 29700,
                    simulateUniV3Interval: false, // simulating uniV2 Interval
                };

                let txs: string[] = [];
                txs.push(
                    this.subject.interface.encodeFunctionData(
                        "updateStrategyParams",
                        [startegyParams]
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
                this.deployerWethAmount = BigNumber.from(10).pow(18);

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

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    // Andrey:
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
                    this.params.uniV3Helper
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
                        this.params.uniV3Helper
                    )
            ).to.not.be.reverted;
        });
    });

    describe("#updateStrategyParams", () => {
        it("set new strategy parameters", async () => {
            await expect(
                this.subject.connect(this.mStrategyAdmin).updateStrategyParams({
                    widthCoefficient: 1,
                    widthTicks: 60,
                    oracleObservationDelta: 300,
                    erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    globalLowerTick: 0,
                    globalUpperTick: 30000,
                    simulateUniV3Interval: false,
                })
            ).to.emit(this.subject, "UpdateStrategyParams");
        });

        describe("edge cases:", () => {
            it("when widthCoefficient <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 0,
                            widthTicks: 1,
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 30000,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when widthTicks <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 1,
                            widthTicks: 0,
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 30000,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when oracleObservationDelta <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 1,
                            widthTicks: 60,
                            oracleObservationDelta: 0,
                            erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 30000,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when erc20MoneyRatioD <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 1,
                            widthTicks: 60,
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: 0,
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 30000,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when erc20MoneyRatioD > DENOMINATOR (1e9), then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 1,
                            widthTicks: 60,
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: BigNumber.from(10).pow(9).add(1),
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 30000,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when minToken0ForOpening <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 1,
                            widthTicks: 60,
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                            minToken0ForOpening: 0,
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 30000,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when minToken1ForOpening <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 1,
                            widthTicks: 60,
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: 0,
                            globalLowerTick: 0,
                            globalUpperTick: 30000,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when (2 ^ 22) / widthTicks < widthCoefficient, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: BigNumber.from(2).pow(20),
                            widthTicks: BigNumber.from(2).pow(20),
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 30000,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when globalUpperTick <= globalLowerTick, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 1,
                            widthTicks: 30,
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 0,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when widthCoefficient * widthTicks <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 0,
                            widthTicks: 30,
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 3000,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when globalIntervalWidth % shortIntervalWidth > 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            widthCoefficient: 1,
                            widthTicks: 30,
                            oracleObservationDelta: 300,
                            erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                            minToken0ForOpening: BigNumber.from(10).pow(6),
                            minToken1ForOpening: BigNumber.from(10).pow(6),
                            globalLowerTick: 0,
                            globalUpperTick: 3001,
                            simulateUniV3Interval: false,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when function called not by strategy admin, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject.connect(this.deployer).updateStrategyParams({
                        widthCoefficient: 1,
                        widthTicks: 30,
                        oracleObservationDelta: 300,
                        erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                        minToken0ForOpening: BigNumber.from(10).pow(6),
                        minToken1ForOpening: BigNumber.from(10).pow(6),
                        globalLowerTick: 0,
                        globalUpperTick: 3000,
                        simulateUniV3Interval: false,
                    })
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

    describe("#rebalance", () => {
        it("performs a rebalance according to strategy params", async () => {
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

            // await this.subject
            //         .connect(this.mStrategyAdmin)
            //         .rebalance(
            //             [0, 0],
            //             [0, 0],
            //             [0, 0],
            //             [0, 0],
            //             [0, 0],
            //             [0, 0],
            //             ethers.constants.MaxUint256,
            //             []
            //         )
        });
    });

    describe("calculateExpectedRatios", () => {
        it.only("correctly calculates the ratio of tokens according to the specification for UniV3 interval simulating", async () => {
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    widthCoefficient: 1,
                    widthTicks: 60,
                    oracleObservationDelta: 300,
                    erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    globalLowerTick: 0,
                    globalUpperTick: 30000,
                    simulateUniV3Interval: true,
                });

            for (var i = 0; i < 10; i++) {
                var lower0Tick = randomInt(10000);
                var lowerTick = lower0Tick + randomInt(10000);
                var upperTick = lowerTick + randomInt(10000) + 1;
                var upper0Tick = upperTick + randomInt(10000);
                var averageTick = lowerTick + randomInt(upperTick - lowerTick);

                const lowerPriceSqrtX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(lowerTick).toString()
                );
                const upperPriceSqrtX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(upperTick).toString()
                );
                const averagePriceSqrtX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(averageTick).toString()
                );
                const lower0PriceSqrtX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(lower0Tick).toString()
                );
                const upper0PriceSqrtX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(upper0Tick).toString()
                );
                expect(
                    lower0PriceSqrtX96 <= lowerPriceSqrtX96 &&
                        lowerPriceSqrtX96 <= averagePriceSqrtX96 &&
                        averagePriceSqrtX96 <= upperPriceSqrtX96 &&
                        upperPriceSqrtX96 <= upper0PriceSqrtX96
                );

                const { token0RatioD, token1RatioD, uniV3RatioD } =
                    await this.subject.callStatic.calculateExpectedRatios({
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
                    } as DomainPositionParamsStruct);

                const averagePriceX96 = averagePriceSqrtX96
                    .mul(averagePriceSqrtX96)
                    .div(BigNumber.from(2).pow(96));

                const expectedToken0RatioDNominatorD = DENOMINATOR.mul(
                    averagePriceX96
                )
                    .div(upperPriceSqrtX96)
                    .sub(
                        DENOMINATOR.mul(averagePriceX96).div(upper0PriceSqrtX96)
                    );

                const expectedToken0RatioDDenominatorD = DENOMINATOR.mul(
                    averagePriceSqrtX96.mul(2)
                )
                    .sub(DENOMINATOR.mul(lower0PriceSqrtX96))
                    .sub(
                        DENOMINATOR.mul(averagePriceX96).div(upper0PriceSqrtX96)
                    );

                const expectedToken0RatioD = DENOMINATOR.mul(
                    expectedToken0RatioDNominatorD
                ).div(expectedToken0RatioDDenominatorD);

                expect(token0RatioD + token1RatioD + uniV3RatioD).to.be.eq(
                    DENOMINATOR.toNumber()
                );
                console.log(
                    expectedToken0RatioD.toString(),
                    token0RatioD.toString()
                );
                console.log(token1RatioD.toString());
                console.log(uniV3RatioD.toString());

                expect(expectedToken0RatioD.sub(token0RatioD).abs()).lte(1);
                // expect(expectedToken1RatioD.sub(token1RatioD).abs()).lte(1);
            }
        });

        it("correctly calculates the ratio of tokens according to the specification for UniV2 interval simulating", async () => {
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    widthCoefficient: 1,
                    widthTicks: 60,
                    oracleObservationDelta: 300,
                    erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    globalLowerTick: 0,
                    globalUpperTick: 30000,
                    simulateUniV3Interval: false,
                });

            for (var i = 0; i < 10; i++) {
                var lowerTick = randomInt(10000);
                var upperTick = lowerTick + randomInt(10000) + 1;
                var averageTick = lowerTick + randomInt(upperTick - lowerTick);
                const lowerPriceSqrtX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(lowerTick).toString()
                );
                const upperPriceSqrtX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(upperTick).toString()
                );
                const averagePriceSqrtX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(averageTick).toString()
                );
                const { token0RatioD, token1RatioD, uniV3RatioD } =
                    await this.subject.callStatic.calculateExpectedRatios({
                        nft: 0,
                        liquidity: 0,
                        lowerTick: 0,
                        upperTick: 0,
                        lower0Tick: 0,
                        upper0Tick: 0,
                        averageTick: 0,
                        lowerPriceSqrtX96: lowerPriceSqrtX96,
                        upperPriceSqrtX96: upperPriceSqrtX96,
                        lower0PriceSqrtX96: 0,
                        upper0PriceSqrtX96: 0,
                        averagePriceSqrtX96: averagePriceSqrtX96,
                        averagePriceX96: 0,
                        spotPriceSqrtX96: 0,
                    } as DomainPositionParamsStruct);

                const expectedToken0RatioD = DENOMINATOR.mul(
                    averagePriceSqrtX96
                )
                    .div(upperPriceSqrtX96)
                    .div(2);
                const expectedToken1RatioD = DENOMINATOR.mul(lowerPriceSqrtX96)
                    .div(averagePriceSqrtX96)
                    .div(2);

                expect(token0RatioD + token1RatioD + uniV3RatioD).to.be.eq(
                    DENOMINATOR.toNumber()
                );
                expect(expectedToken0RatioD.sub(token0RatioD).abs()).lte(1);
                expect(expectedToken1RatioD.sub(token1RatioD).abs()).lte(1);
            }
        });
    });

    describe("calculateDomainPositionParams", () => {
        it("", async () => {});
    });

    describe("calculateExpectedTokenAmountsInToken0", () => {
        it("", async () => {});
    });

    describe("calculateCurrentTokenAmountsInToken0", () => {
        it("", async () => {});
    });

    // Artyom:
    describe("calculateCurrentTokenAmounts", () => {});
    describe("calculateExpectedTokenAmounts", () => {});
    describe("calculateExtraTokenAmountsForMoneyVault", () => {});
    describe("calculateMissingTokenAmounts", () => {});
    describe("swapTokens", () => {});

    ContractMetaBehaviour.call(this, {
        contractName: "HStrategy",
        contractVersion: "1.0.0",
    });
});
