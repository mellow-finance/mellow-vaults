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
} from "./types/MockHStrategy";
import Exceptions from "./library/Exceptions";
import { TickMath } from "@uniswap/v3-sdk";
import { RebalanceRestrictionsStruct } from "./types/HStrategy";
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
                    oracleObservationDelta: 150,
                    erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5), // 5%
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    globalLowerTick: 23400,
                    globalUpperTick: 29700,
                    tickNeighborhood: 0,
                    maxTickDeviation: 100,
                    simulateUniV3Interval: false, // simulating uniV2 Interval
                };
                this.strategyParams = strategyParams;

                let txs: string[] = [];
                txs.push(
                    this.subject.interface.encodeFunctionData(
                        "updateStrategyParams",
                        [strategyParams]
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
                    const pool = await this.subject.pool();
                    const priceInfo =
                        await this.uniV3Helper.getAverageTickAndSqrtSpotPrice(
                            pool,
                            strategyParams.oracleObservationDelta
                        );
                    return await this.hStrategyHelper.calculateDomainPositionParams(
                        priceInfo.averageTick,
                        priceInfo.sqrtSpotPriceX96,
                        strategyParams,
                        await this.uniV3Vault.uniV3Nft(),
                        this.positionManager.address
                    );
                };

                this.tvlToken0 = async () => {
                    const Q96 = BigNumber.from(2).pow(96);
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

    // Andrey:
    describe.only("#constructor", () => {
        it("deploys a new contract", async () => {
            expect(this.subject.address).to.not.eq(
                ethers.constants.AddressZero
            );
        });
    });

    describe.only("#createStrategy", () => {
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

    describe.only("#updateStrategyParams", () => {
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
                    tickNeighborhood: 0,
                    maxTickDeviation: 100,
                    simulateUniV3Interval: false,
                } as StrategyParamsStruct)
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
                            simulateUniV3Interval: false,
                        } as StrategyParamsStruct)
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
                            simulateUniV3Interval: false,
                        } as StrategyParamsStruct)
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
                            simulateUniV3Interval: false,
                        } as StrategyParamsStruct)
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
                            tickNeighborhood: 0,
                            maxTickDeviation: 100,
                            simulateUniV3Interval: false,
                        } as StrategyParamsStruct)
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
                        tickNeighborhood: 0,
                        maxTickDeviation: 100,
                        simulateUniV3Interval: false,
                    } as StrategyParamsStruct)
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
        });
    });

    describe.only("#manualPull", () => {
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

    describe.only("#rebalance", () => {
        it("performs a rebalance according to strategy params", async () => {
            await this.subject
                .connect(this.mStrategyAdmin)
                .updateStrategyParams({
                    widthCoefficient: 1,
                    widthTicks: 60,
                    oracleObservationDelta: 300,
                    erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5),
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    globalLowerTick: -870000,
                    globalUpperTick: 870000,
                    tickNeighborhood: 0,
                    maxTickDeviation: 100,
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
            ).not.to.be.reverted;
            console.log("Done, going back");
            for (var i = 0; i < 5; i++) {
                console.log(i);
                await push(BigNumber.from(10).pow(12), "USDC");
                await sleep(this.governanceDelay);
            }

            // await expect(
            await this.subject
                .connect(this.mStrategyAdmin)
                .rebalance(restrictions, []);
            // ).not.to.be.reverted;
        });
    });

    describe.only("calculateExpectedRatios", () => {
        it("correctly calculates the ratio of tokens according to the specification for UniV3 interval simulating", async () => {
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
                    tickNeighborhood: 0,
                    maxTickDeviation: 100,
                    simulateUniV3Interval: true,
                } as StrategyParamsStruct);

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
                var strategyParams = this.strategyParams;
                strategyParams.simulateUniV3Interval = true;
                const { token0RatioD, token1RatioD, uniV3RatioD } =
                    await this.hStrategyHelper.callStatic.calculateExpectedRatios(
                        strategyParams,
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
                    .div(BigNumber.from(2).pow(96));

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
                    .div(BigNumber.from(2).pow(96));

                const expectedTokensRatioDDenominatorD = DENOMINATOR.mul(
                    averagePriceSqrtX96.mul(2)
                )
                    .div(BigNumber.from(2).pow(96))
                    .sub(
                        DENOMINATOR.mul(lower0PriceSqrtX96).div(
                            BigNumber.from(2).pow(96)
                        )
                    )
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
                    tickNeighborhood: 0,
                    maxTickDeviation: 100,
                    simulateUniV3Interval: false,
                } as StrategyParamsStruct);

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
                var strategyParams = this.strategyParams;
                strategyParams.simulateUniV3Interval = false;
                const { token0RatioD, token1RatioD, uniV3RatioD } =
                    await this.hStrategyHelper.callStatic.calculateExpectedRatios(
                        strategyParams,
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
                            lower0PriceSqrtX96: 0,
                            upper0PriceSqrtX96: 0,
                            averagePriceSqrtX96: averagePriceSqrtX96,
                            averagePriceX96: 0,
                            spotPriceSqrtX96: 0,
                        } as DomainPositionParamsStruct
                    );

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

    describe.only("calculateDomainPositionParams", () => {
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
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });

                const globalUpperTick = upperTick + randomInt(10);
                const globalLowerTick = lowerTick - randomInt(100);

                const strategyParams = {
                    widthCoefficient: 0,
                    widthTicks: 0,
                    oracleObservationDelta: 0,
                    erc20MoneyRatioD: 0,
                    minToken0ForOpening: 0,
                    minToken1ForOpening: 0,
                    globalLowerTick: globalLowerTick,
                    globalUpperTick: globalUpperTick,
                    tickNeighborhood: 0,
                    maxTickDeviation: 100,
                    simulateUniV3Interval: false,
                } as StrategyParamsStruct;

                const result =
                    await this.hStrategyHelper.calculateDomainPositionParams(
                        averageTick,
                        BigNumber.from(
                            TickMath.getSqrtRatioAtTick(averageTick).toString()
                        ),
                        strategyParams,
                        tokenId,
                        this.positionManager.address
                    );

                expect(result.lower0Tick).to.be.eq(globalLowerTick);
                expect(result.upper0Tick).to.be.eq(globalUpperTick);

                expect(result.lowerTick).to.be.eq(lowerTick);
                expect(result.upperTick).to.be.eq(upperTick);

                expect(result.lower0PriceSqrtX96).to.be.eq(
                    BigNumber.from(
                        TickMath.getSqrtRatioAtTick(globalLowerTick).toString()
                    )
                );
                expect(result.upper0PriceSqrtX96).to.be.eq(
                    BigNumber.from(
                        TickMath.getSqrtRatioAtTick(globalUpperTick).toString()
                    )
                );

                expect(result.lowerPriceSqrtX96).to.be.eq(
                    BigNumber.from(
                        TickMath.getSqrtRatioAtTick(lowerTick).toString()
                    )
                );
                expect(result.upperPriceSqrtX96).to.be.eq(
                    BigNumber.from(
                        TickMath.getSqrtRatioAtTick(upperTick).toString()
                    )
                );

                expect(result.liquidity).to.be.gt(0);
                expect(result.nft).to.be.eq(tokenId);
                expect(result.averageTick).to.be.eq(averageTick);

                const priceSqrtX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(averageTick).toString()
                );
                expect(result.averagePriceSqrtX96).to.be.eq(priceSqrtX96);
                const priceX96 = priceSqrtX96
                    .mul(priceSqrtX96)
                    .div(BigNumber.from(2).pow(96));

                expect(result.averagePriceX96).to.be.eq(priceX96);
                expect(result.spotPriceSqrtX96).to.be.eq(priceSqrtX96);
            }
        });
    });

    describe.only("calculateExpectedTokenAmountsInToken0", () => {
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

                var strategyParams = {
                    widthCoefficient: 1,
                    widthTicks: 0,
                    oracleObservationDelta: 300,
                    erc20MoneyRatioD: BigNumber.from(10)
                        .pow(7)
                        .mul(randomInt(100)),
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    globalLowerTick: 0,
                    globalUpperTick: 30000,
                    tickNeighborhood: 0,
                    maxTickDeviation: 100,
                    simulateUniV3Interval: false,
                };

                const {
                    erc20TokensAmountInToken0,
                    uniV3TokensAmountInToken0,
                    moneyTokensAmountInToken0,
                    totalTokensInToken0,
                } = await this.hStrategyHelper.calculateExpectedTokenAmountsInToken0(
                    tokenAmounts,
                    ratios,
                    strategyParams
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
                    strategyParams.erc20MoneyRatioD.add(10)
                );
                expect(realRatio).to.be.gte(
                    strategyParams.erc20MoneyRatioD.sub(10)
                );
            }
        });
    });

    describe.only("calculateCurrentTokenAmountsInToken0", () => {
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
                        .mul(BigNumber.from(2).pow(96).div(1000)),
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
                            .mul(BigNumber.from(2).pow(96))
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

    // Artyom:
    describe.only("#calculateCurrentTokenAmounts", () => {
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
                            [
                                BigNumber.from(2).pow(96),
                                BigNumber.from(2).pow(96),
                            ],
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

    describe.only("calculateExpectedTokenAmounts", () => {
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
            strategyParams: StrategyParamsStruct
        ) => {
            const positionParams = await this.getPositionParams();
            const ratios = await this.hStrategyHelper.calculateExpectedRatios(
                strategyParams,
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
                    strategyParams
                );
            return await this.hStrategyHelper.calculateExpectedTokenAmounts(
                ratios,
                expectedInToken0,
                positionParams
            );
        };

        const requiredExpectedTokenAmounts = async (
            strategyParams: StrategyParamsStruct
        ) => {
            const positionParams = await this.getPositionParams();
            const ratios = await this.hStrategyHelper.calculateExpectedRatios(
                strategyParams,
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
                    strategyParams
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

        const compareAmounts = async () => {
            const strategyParams = await this.subject.strategyParams();
            const required = await requiredExpectedTokenAmounts(strategyParams);
            const actual = await actualExpectedTokenAmounts(strategyParams);
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

        describe("compare to typescript", () => {
            it("equals to typescript", async () => {
                await compareAmounts();
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6).mul(2000)
                );
                await compareAmounts();
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
                await compareAmounts();
            });
        });

        const compareCurrentAndExpected = async () => {
            const positionParams = await this.getPositionParams();
            const strategyParams = await this.subject.strategyParams();
            const expected = await actualExpectedTokenAmounts(strategyParams);
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

    describe.only("calculateExtraTokenAmountsForMoneyVault", () => {
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
            const strategyParams = await this.subject.strategyParams();
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
                strategyParams,
                position
            );
            const amountsInToken0 =
                await this.hStrategyHelper.calculateExpectedTokenAmountsInToken0(
                    currentAmountsInToken0,
                    ratios,
                    strategyParams
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

    describe("  ", () => {});

    describe("swapTokens", () => {
        describe("on initial", () => {
            beforeEach(async () => {
                this.mintMockPosition();
            });
            it("works", async () => {});
        });
    });

    ContractMetaBehaviour.call(this, {
        contractName: "HStrategy",
        contractVersion: "1.0.0",
    });
});
