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
import { TickMath } from "@uniswap/v3-sdk";
import {
    OracleParamsStruct,
    RebalanceTokenAmountsStruct,
} from "./types/HStrategy";
import {
    DomainPositionParamsStruct,
    ExpectedRatiosStruct,
    TokenAmountsInToken0Struct,
} from "./types/HStrategyHelper";

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
                ).deploy(
                    uniswapV3PositionManager,
                    uniswapV3Router,
                    uniV3Helper,
                    hStrategyHelper
                );
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
                    this.params.admin
                );
                await hStrategy.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.uniV3Vault,
                    this.params.fee,
                    this.params.admin
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
                    halfOfShortInterval: 900,
                    tickNeighborhood: 100,
                    domainLowerTick: 23400,
                    domainUpperTick: 29700,
                };
                this.strategyParams = strategyParams;

                const oracleParams = {
                    averagePriceTimeSpan: 150,
                    maxTickDeviation: 100,
                };
                this.oracleParams = oracleParams;

                const ratioParams = {
                    erc20CapitalRatioD: BigNumber.from(10).pow(7).mul(5), // 5%
                    minCapitalDeviationD: BigNumber.from(10).pow(7).mul(1), // 1%
                    minRebalanceDeviationD: BigNumber.from(10).pow(7).mul(1), // 1%
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
                txs.push(
                    this.subject.interface.encodeFunctionData(
                        "updateSwapFees",
                        [3000]
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
                    const slot0 = await this.pool.slot0();
                    const params =
                        await this.hStrategyHelper.callStatic.calculateAndCheckDomainPositionParams(
                            slot0.tick,
                            strategyParams,
                            await this.uniV3Vault.uniV3Nft(),
                            this.positionManager.address
                        );
                    return params;
                };

                this.getSqrtRatioAtTick = (tick: number) => {
                    return BigNumber.from(
                        TickMath.getSqrtRatioAtTick(
                            BigNumber.from(tick).toNumber()
                        ).toString()
                    );
                };

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
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
                    this.params.admin
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
                        this.params.admin
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
            it("when averagePriceTimeSpan <= 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateOracleParams({
                            ...this.oracleParams,
                            averagePriceTimeSpan: 0,
                        })
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("when erc20CapitalRatioD > DENOMINATOR (1e9), then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateRatioParams({
                            ...this.ratioParams,
                            erc20CapitalRatioD: DENOMINATOR.add(1),
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

            it("when globalUpperTick <= globalLowerTick, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            domainLowerTick: 0,
                            domainUpperTick: 0,
                        } as StrategyParamsStruct)
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });

            it("when globalIntervalWidth % halfOfShortInterval > 0, then reverts with INVARIANT", async () => {
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            ...this.strategyParams,
                            halfOfShortInterval: 30,
                            domainLowerTick: 0,
                            domainUpperTick: 3001,
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

    describe("#rebalance", () => {
        it("performs a rebalance according to strategy params", async () => {
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...this.strategyParams,
                    tickNeighborhood: 10,
                    halfOfShortInterval: 60,
                    domainlLowerTick: -870000,
                    domainUpperTick: 870000,
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
                pulledFromUniV3Vault: [0, 0],
                pulledToUniV3Vault: [0, 0],
                swappedAmounts: [0, 0],
                burnedAmounts: [0, 0],
                deadline: ethers.constants.MaxUint256,
            } as RebalanceTokenAmountsStruct;
            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            ).not.to.be.reverted;

            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .rebalance(restrictions, [])
            );

            for (var i = 0; i < 4; i++) {
                await push(BigNumber.from(10).pow(21), "WETH");
                await sleep(this.governanceDelay);
            }

            {
                const ratioParams = await this.subject.ratioParams();
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .updateRatioParams({
                        ...ratioParams,
                        minErc20CaptialDeviationD: 0,
                        minRebalanceDeviationD: 1,
                    } as RatioParamsStruct);
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
                    halfOfShortInterval: 60,
                    tickNeighborhood: 10,
                    domainLowerTick: tickLower,
                    domainUpperTick: tickUpper + 60,
                } as StrategyParamsStruct);
            await sleep(this.governanceDelay);
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
            await sleep(this.governanceDelay);

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
    });

    describe("calculateExpectedRatios", () => {
        it("correctly calculates the ratio of tokens according to the specification for UniV3 interval simulating", async () => {
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    ...this.strategyParams,
                } as StrategyParamsStruct);

            for (var i = 0; i < 10; i++) {
                var domainLowerTick = 100 + randomInt(100);
                var lowerTick = domainLowerTick + randomInt(100);
                var upperTick = lowerTick + randomInt(100) + 1;
                var domainUpperTick = upperTick + randomInt(100);
                var averageTick = lowerTick + randomInt(upperTick - lowerTick);

                const lowerPriceSqrtX96 = this.getSqrtRatioAtTick(lowerTick);
                const upperPriceSqrtX96 = this.getSqrtRatioAtTick(upperTick);
                const averagePriceSqrtX96 =
                    this.getSqrtRatioAtTick(averageTick);
                const domainLowerPriceSqrtX96 =
                    this.getSqrtRatioAtTick(domainLowerTick);
                const domainUpperPriceSqrtX96 =
                    this.getSqrtRatioAtTick(domainUpperTick);
                expect(
                    domainLowerPriceSqrtX96 <= lowerPriceSqrtX96 &&
                        lowerPriceSqrtX96 <= averagePriceSqrtX96 &&
                        averagePriceSqrtX96 <= upperPriceSqrtX96 &&
                        upperPriceSqrtX96 <= domainUpperPriceSqrtX96
                );

                const { token0RatioD, token1RatioD, uniV3RatioD } =
                    await this.hStrategyHelper.callStatic.calculateExpectedRatios(
                        {
                            nft: 0,
                            liquidity: 0,
                            lowerTick: 0,
                            upperTick: 0,
                            domainLowerTick: 0,
                            domainUpperTick: 0,
                            averageTick: 0,
                            lowerPriceSqrtX96: lowerPriceSqrtX96,
                            upperPriceSqrtX96: upperPriceSqrtX96,
                            domainLowerPriceSqrtX96: domainLowerPriceSqrtX96,
                            domainUpperPriceSqrtX96: domainUpperPriceSqrtX96,
                            intervalPriceSqrtX96: averagePriceSqrtX96,
                            spotPriceX96: 0,
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
                        DENOMINATOR.mul(averagePriceX96).div(
                            domainUpperPriceSqrtX96
                        )
                    );

                const expectedToken1RatioDNominatorD = DENOMINATOR.mul(
                    lowerPriceSqrtX96
                )
                    .sub(DENOMINATOR.mul(domainLowerPriceSqrtX96))
                    .div(Q96);

                const expectedTokensRatioDDenominatorD = DENOMINATOR.mul(
                    averagePriceSqrtX96.mul(2)
                )
                    .div(Q96)
                    .sub(DENOMINATOR.mul(domainLowerPriceSqrtX96).div(Q96))
                    .sub(
                        DENOMINATOR.mul(averagePriceX96).div(
                            domainUpperPriceSqrtX96
                        )
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
                    domainLowerTick: globalLowerTick,
                    domainUpperTick: globalUpperTick,
                } as StrategyParamsStruct;

                const result =
                    await this.hStrategyHelper.calculateAndCheckDomainPositionParams(
                        averageTick,
                        strategyParams,
                        tokenId,
                        this.positionManager.address
                    );

                expect(result.domainLowerTick).to.be.eq(globalLowerTick);
                expect(result.domainUpperTick).to.be.eq(globalUpperTick);

                expect(result.lowerTick).to.be.eq(lowerTick);
                expect(result.upperTick).to.be.eq(upperTick);

                expect(result.domainLowerPriceSqrtX96).to.be.eq(
                    this.getSqrtRatioAtTick(globalLowerTick)
                );
                expect(result.domainUpperPriceSqrtX96).to.be.eq(
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

                const priceSqrtX96 = this.getSqrtRatioAtTick(averageTick);
                expect(result.intervalPriceSqrtX96).to.be.eq(priceSqrtX96);
                const priceX96 = priceSqrtX96.mul(priceSqrtX96).div(Q96);
                expect(result.spotPriceX96).to.be.eq(priceX96);
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
                    erc20CapitalRatioD: BigNumber.from(10)
                        .pow(7)
                        .mul(randomInt(100)),
                    minCapitalDeviationD: 0,
                    minRebalanceDeviationD: 0,
                } as RatioParamsStruct;

                const {
                    erc20TokensAmountInToken0,
                    uniV3TokensAmountInToken0,
                    moneyTokensAmountInToken0,
                    totalTokensInToken0,
                } = await this.hStrategyHelper.calculateExpectedTokenAmountsInToken0(
                    tokenAmounts.totalTokensInToken0,
                    ratios,
                    ratioParams
                );

                expect(totalTokensInToken0).to.be.eq(
                    tokenAmounts.totalTokensInToken0
                );
                expect(erc20TokensAmountInToken0).to.be.eq(
                    totalTokensInToken0
                        .mul(ratioParams.erc20CapitalRatioD)
                        .div(DENOMINATOR)
                );

                const exptectedOnUniV3 = totalTokensInToken0
                    .sub(erc20TokensAmountInToken0)
                    .mul(ratios.uniV3RatioD)
                    .div(DENOMINATOR);
                const exptectedOnMoney = totalTokensInToken0
                    .sub(erc20TokensAmountInToken0)
                    .sub(exptectedOnUniV3);

                expect(
                    uniV3TokensAmountInToken0
                        .sub(exptectedOnUniV3)
                        .abs()
                        .mul(100)
                        .div(exptectedOnUniV3)
                        .lte(1)
                );
                expect(
                    moneyTokensAmountInToken0
                        .sub(exptectedOnMoney)
                        .abs()
                        .mul(100)
                        .div(exptectedOnMoney)
                        .lte(1)
                );
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
                    domainLowerTick: tickLower - 600,
                    domainUpperTick: tickUpper + 600,
                    halfOfShortInterval: 60,
                    tickNeighborhood: 10,
                });
        });
        describe("initial zero", () => {
            it("equals zero", async () => {
                const positionParams = await this.getPositionParams();
                const result =
                    await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
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
                        await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
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
                        await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
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
                        await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
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
                        await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
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
            xit("works", async () => {
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
                        await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
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
                        await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
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

    describe("calculateExpectedTokenAmountsByExpectedRatios", () => {
        beforeEach(async () => {
            await this.mintMockPosition();
            const { nft } = await this.getPositionParams();
            const { tickLower, tickUpper } =
                await this.positionManager.positions(nft);
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    domainLowerTick: tickLower - 600,
                    domainUpperTick: tickUpper + 600,
                    halfOfShortInterval: 60,
                    tickNeighborhood: 10,
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
                await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    positionParams
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.callStatic.calculateCurrentCapitalInToken0(
                    positionParams,
                    currentAmounts
                );
            const expectedInToken0 =
                await this.hStrategyHelper.callStatic.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    ratioParams
                );
            const params =
                await this.hStrategyHelper.callStatic.calculateExpectedTokenAmountsByExpectedRatios(
                    ratios,
                    expectedInToken0,
                    positionParams,
                    this.uniV3Helper.address
                );
            return params;
        };

        const requiredExpectedTokenAmounts = async (
            ratioParams: RatioParamsStruct
        ) => {
            const positionParams = await this.getPositionParams();
            const ratios =
                await this.hStrategyHelper.callStatic.calculateExpectedRatios(
                    positionParams
                );
            const currentAmounts =
                await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    positionParams
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.callStatic.calculateCurrentCapitalInToken0(
                    positionParams,
                    currentAmounts
                );
            const expectedInToken0 =
                await this.hStrategyHelper.callStatic.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    ratioParams
                );
            const erc20Token0 = expectedInToken0.erc20TokensAmountInToken0
                .mul(ratios.token0RatioD)
                .div(ratios.token0RatioD + ratios.token1RatioD);
            const erc20Token1 = expectedInToken0.erc20TokensAmountInToken0
                .sub(erc20Token0)
                .mul(positionParams.spotPriceX96)
                .div(Q96);
            const moneyToken0 = expectedInToken0.moneyTokensAmountInToken0
                .mul(ratios.token0RatioD)
                .div(ratios.token0RatioD + ratios.token1RatioD);
            const moneyToken1 = expectedInToken0.moneyTokensAmountInToken0
                .sub(moneyToken0)
                .mul(positionParams.spotPriceX96)
                .div(Q96);
            const uniV3RatioX96 = positionParams.intervalPriceSqrtX96
                .sub(positionParams.lowerPriceSqrtX96)
                .mul(Q96)
                .div(
                    positionParams.upperPriceSqrtX96.sub(
                        positionParams.intervalPriceSqrtX96
                    )
                )
                .mul(positionParams.upperPriceSqrtX96)
                .div(positionParams.intervalPriceSqrtX96);
            const uniV3TokenAmounts =
                await this.uniV3Helper.getPositionTokenAmountsByCapitalOfToken0(
                    positionParams.lowerPriceSqrtX96,
                    positionParams.upperPriceSqrtX96,
                    positionParams.intervalPriceSqrtX96,
                    positionParams.spotPriceX96,
                    expectedInToken0.uniV3TokensAmountInToken0
                );
            const uniV3Token0 = uniV3TokenAmounts[0];
            const uniV3Token1 = uniV3TokenAmounts[1];
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
            const priceX96 = positionParams.spotPriceX96;
            const spotPriceX96 = positionParams.spotPriceX96;
            const totalCapital1 = expected.erc20Token1
                .add(expected.moneyToken1)
                .mul(Q96)
                .div(priceX96)
                .add(expected.uniV3Token1.mul(Q96).div(spotPriceX96));
            const totalCapitalExpected = totalCapital0.add(totalCapital1);
            const currentAmountsInToken0 =
                await this.hStrategyHelper.callStatic.calculateCurrentCapitalInToken0(
                    await this.getPositionParams(),
                    await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
                        this.erc20Vault.address,
                        this.yearnVault.address,
                        positionParams
                    )
                );
            const absDiff = currentAmountsInToken0
                .sub(totalCapitalExpected)
                .abs();
            expect(absDiff.mul(100).lte(currentAmountsInToken0)).to.be.true;
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
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    domainLowerTick: tickLower - 600,
                    domainUpperTick: tickUpper + 600,
                    halfOfShortInterval: 60,
                    tickNeighborhood: 10,
                });
        });

        const checkExtraAmounts = async () => {
            const ratioParams = await this.subject.ratioParams();
            const position = await this.getPositionParams();
            const currentAmounts =
                await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    position
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.callStatic.calculateCurrentCapitalInToken0(
                    position,
                    currentAmounts
                );
            const ratios =
                await this.hStrategyHelper.callStatic.calculateExpectedRatios(
                    position
                );
            const amountsInToken0 =
                await this.hStrategyHelper.callStatic.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    ratioParams
                );
            const expectedAmounts =
                await this.hStrategyHelper.callStatic.calculateExpectedTokenAmountsByExpectedRatios(
                    ratios,
                    amountsInToken0,
                    position,
                    this.uniV3Helper.address
                );
            const actualExtraAmounts =
                await this.hStrategyHelper.callStatic.calculateExtraTokenAmountsForMoneyVault(
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
                    .sub(actualExtraAmounts[0])
                    .toNumber()
            ).to.be.eq(0);
            expect(
                requiredExtraAmounts.token1Amount
                    .sub(actualExtraAmounts[1])
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
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    domainLowerTick: tickLower - 600,
                    domainUpperTick: tickUpper + 600,
                    halfOfShortInterval: 60,
                    tickNeighborhood: 10,
                });
        });

        const checkMissingAmounts = async () => {
            const ratioParams = await this.subject.ratioParams();
            const position = await this.getPositionParams();
            const currentAmounts =
                await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    position
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.callStatic.calculateCurrentCapitalInToken0(
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
                await this.hStrategyHelper.callStatic.calculateExpectedTokenAmountsByExpectedRatios(
                    ratios,
                    amountsInToken0,
                    position,
                    this.uniV3Helper.address
                );
            const actualMissingAmounts =
                await this.hStrategyHelper.callStatic.calculateMissingTokenAmounts(
                    this.yearnVault.address,
                    expectedAmounts,
                    position,
                    position.liquidity
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
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    domainLowerTick: tickLower - 600,
                    domainUpperTick: tickUpper + 600,
                    halfOfShortInterval: 60,
                    tickNeighborhood: 10,
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
                await this.hStrategyHelper.callStatic.calculateCurrentTokenAmounts(
                    this.erc20Vault.address,
                    this.yearnVault.address,
                    position
                );
            const currentAmountsInToken0 =
                await this.hStrategyHelper.callStatic.calculateCurrentCapitalInToken0(
                    position,
                    currentAmounts
                );
            const ratios =
                await this.hStrategyHelper.callStatic.calculateExpectedRatios(
                    position
                );
            const amountsInToken0 =
                await this.hStrategyHelper.callStatic.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    ratioParams
                );
            const expectedAmounts =
                await this.hStrategyHelper.callStatic.calculateExpectedTokenAmountsByExpectedRatios(
                    ratios,
                    amountsInToken0,
                    position,
                    this.uniV3Helper.address
                );
            return { currentAmounts, expectedAmounts };
        };

        describe("emits event", () => {
            it("emits", async () => {
                const { currentAmounts, expectedAmounts } =
                    await getSwapParams();
                await expect(
                    this.subject.swapTokens(expectedAmounts, currentAmounts, {
                        pulledToUniV3Vault: [
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
                        pulledToUniV3Vault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        pulledFromUniV3Vault: [
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ],
                        swappedAmounts: [
                            ethers.constants.MaxInt256,
                            ethers.constants.MaxInt256.mul(-1),
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
