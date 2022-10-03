import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    sleep,
    withSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Helper,
    UniV3Vault,
    ISwapRouter as SwapRouterInterface,
    HStrategyHelper,
    IUniswapV3Pool,
} from "../types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    setupVault,
    combineVaults,
    TRANSACTION_GAS_LIMITS,
} from "../../deploy/0000_utils";
import { Contract } from "@ethersproject/contracts";
import {
    MockHStrategy,
    StrategyParamsStruct,
    RatioParamsStruct,
} from "../types/MockHStrategy";
import { TickMath } from "@uniswap/v3-sdk";
import { RebalanceTokenAmountsStruct } from "../types/HStrategy";
import { expect } from "chai";

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

contract<MockHStrategy, DeployOptions, CustomContext>(
    "Integration__hstrategy_erc20_yearn",
    function () {
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
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let yearnVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    let uniV3VaultNft = startNft + 2;
                    let erc20RootVaultNft = startNft + 3;
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

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
                    const { address: hStrategyHelper } =
                        await ethers.getContract("HStrategyHelper");

                    this.hStrategyHelper = await ethers.getContractAt(
                        "HStrategyHelper",
                        hStrategyHelper
                    );

                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                3000,
                                uniV3Helper,
                            ],
                        }
                    );
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
                        minRebalanceDeviationD: BigNumber.from(10)
                            .pow(7)
                            .mul(1), // 1%
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

                    this.deployerUsdcAmount = BigNumber.from(10)
                        .pow(9)
                        .mul(3000);
                    this.deployerWethAmount = BigNumber.from(10)
                        .pow(18)
                        .mul(4000);

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
                        await this.weth.approve(
                            addr,
                            ethers.constants.MaxUint256
                        );
                        await this.usdc.approve(
                            addr,
                            ethers.constants.MaxUint256
                        );
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

        const getAverageTick = async () => {
            // returns average tick for last 30 minutes
            let { tick } = await this.pool.slot0();
            const deviation = (
                await this.uniV3Helper.getTickDeviationForTimeSpan(
                    tick,
                    this.pool.address,
                    30 * 60
                )
            ).deviation;
            return tick - deviation;
        };
        const getSpotTick = async () => {
            var result: number;
            let { tick } = await this.pool.slot0();
            result = tick;
            return result;
        };

        describe("#rebalance", () => {
            const intervals = [[600, "small"]];
            intervals.forEach((data) => {
                it(`works correctly for ${data[1]} interval`, async () => {
                    const centralTick = await getAverageTick();
                    const domainLowerTick =
                        centralTick - (data[0] as number) - (centralTick % 600);
                    const domainUpperTick =
                        centralTick + (data[0] as number) - (centralTick % 600);
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams({
                            halfOfShortInterval: 60,
                            tickNeighborhood: 10,
                            domainLowerTick: domainLowerTick,
                            domainUpperTick: domainUpperTick,
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
                        [
                            pullExistentials[0].mul(10),
                            pullExistentials[1].mul(10),
                        ],
                        0,
                        []
                    );

                    // normal deposit
                    await this.erc20RootVault.deposit(
                        [
                            BigNumber.from(10).pow(14),
                            BigNumber.from(10).pow(14),
                        ],
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
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .updateRatioParams({
                            erc20CapitalRatioD: BigNumber.from(10)
                                .pow(7)
                                .mul(5),
                            minCapitalDeviationD: 0,
                            minRebalanceDeviationD: 1,
                        } as RatioParamsStruct);
                    await sleep(this.governanceDelay);

                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.erc20RootVaultNft, {
                            strategyTreasury: this.erc20Vault.address,
                            strategyPerformanceTreasury:
                                this.erc20Vault.address,
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

                    const compare = (
                        x: BigNumber,
                        y: BigNumber,
                        delta: number
                    ) => {
                        const val = x.sub(y).abs();
                        const deltaX = x.mul(delta).div(100);
                        const deltaY = y.mul(delta).div(100);
                        let maxDelta = deltaX.lt(deltaY) ? deltaY : deltaX;
                        maxDelta = maxDelta.add(1000);
                        expect(val.lte(maxDelta)).to.be.true;
                    };

                    const checkState = async (spotTick: number) => {
                        const erc20Tvl = (await this.erc20Vault.tvl())
                            .minTokenAmounts;
                        const moneyTvl = (await this.yearnVault.tvl())
                            .minTokenAmounts;
                        const positions = await this.positionManager.positions(
                            await this.uniV3Vault.uniV3Nft()
                        );
                        const lowerTick = positions.tickLower;
                        const upperTick = positions.tickUpper;
                        const strategyParams =
                            await this.subject.strategyParams();
                        const lower0Tick = strategyParams.domainLowerTick;
                        const upper0Tick = strategyParams.domainUpperTick;
                        if (spotTick < lowerTick) {
                            spotTick = lowerTick;
                        } else if (spotTick > upperTick) {
                            spotTick = upperTick;
                        }
                        const erc20CapitalRatioD = (
                            await this.subject.ratioParams()
                        ).erc20CapitalRatioD;
                        const { liquidity } =
                            await this.positionManager.positions(
                                await this.uniV3Vault.uniV3Nft()
                            );
                        const uniV3Tvl =
                            await this.uniV3Vault.liquidityToTokenAmounts(
                                liquidity
                            );
                        this.getSqrtRatioAtTick = (tick: number) => {
                            return BigNumber.from(
                                TickMath.getSqrtRatioAtTick(
                                    BigNumber.from(tick).toNumber()
                                ).toString()
                            );
                        };
                        const sqrtA = this.getSqrtRatioAtTick(lowerTick);
                        const sqrtB = this.getSqrtRatioAtTick(upperTick);
                        const sqrtA0 = this.getSqrtRatioAtTick(lower0Tick);
                        const sqrtB0 = this.getSqrtRatioAtTick(upper0Tick);
                        const sqrtC0 = this.getSqrtRatioAtTick(spotTick);

                        // devide all by sqrtC0
                        const getWxD = () => {
                            const nominatorX96 = Q96.mul(sqrtC0)
                                .div(sqrtB)
                                .sub(Q96.mul(sqrtC0).div(sqrtB0));
                            const denominatorX96 = Q96.mul(2)
                                .sub(Q96.mul(sqrtA0).div(sqrtC0))
                                .sub(Q96.mul(sqrtC0).div(sqrtB0));
                            return nominatorX96
                                .mul(DENOMINATOR)
                                .div(denominatorX96);
                        };

                        const getWyD = () => {
                            const nominatorX96 = Q96.mul(sqrtA)
                                .div(sqrtC0)
                                .sub(Q96.mul(sqrtA0).div(sqrtC0));
                            const denominatorX96 = Q96.mul(2)
                                .sub(Q96.mul(sqrtA0).div(sqrtC0))
                                .sub(Q96.mul(sqrtC0).div(sqrtB0));
                            return nominatorX96
                                .mul(DENOMINATOR)
                                .div(denominatorX96);
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
                        const spotPriceX96 = sqrtC0.mul(sqrtC0).div(Q96);

                        const totalCapital = totalToken0.add(
                            totalToken1.mul(Q96).div(spotPriceX96)
                        );
                        const erc20Capital = totalCapital
                            .mul(erc20CapitalRatioD)
                            .div(DENOMINATOR);

                        const uniV3Capital = totalCapital
                            .sub(erc20Capital)
                            .mul(wUniD)
                            .div(DENOMINATOR);
                        const moneyCapital = totalCapital
                            .sub(uniV3Capital)
                            .sub(erc20Capital);

                        const currentUniV3Capital = uniV3Tvl[0].add(
                            uniV3Tvl[1].mul(Q96).div(spotPriceX96)
                        );
                        const expectedMoneyToken0Amount = moneyCapital
                            .mul(wxD)
                            .div(wxD.add(wyD));
                        const expectedMoneyToken1Amount = moneyCapital
                            .mul(wyD)
                            .div(wxD.add(wyD))
                            .mul(spotPriceX96)
                            .div(Q96);

                        compare(uniV3Capital, currentUniV3Capital, 3);
                        compare(expectedMoneyToken0Amount, moneyTvl[0], 1);
                        compare(expectedMoneyToken1Amount, moneyTvl[1], 1);
                    };

                    const interationsNumber = 10;
                    for (var i = 0; i < interationsNumber; i++) {
                        var doFullRebalance = i % 2 == 0;
                        if (doFullRebalance) {
                            if (i & 2) {
                                const initialTick = await getSpotTick();
                                var currentTick = initialTick;
                                while (currentTick - initialTick >= -100) {
                                    await push(
                                        BigNumber.from(10).pow(11).mul(5),
                                        "USDC"
                                    );
                                    await sleep(this.governanceDelay);
                                    currentTick = await getSpotTick();
                                }
                            } else {
                                const initialTick = await getSpotTick();
                                var currentTick = initialTick;
                                while (initialTick - currentTick >= -100) {
                                    await push(
                                        BigNumber.from(10).pow(21),
                                        "WETH"
                                    );
                                    await sleep(this.governanceDelay);
                                    currentTick = await getSpotTick();
                                }
                            }
                        } else {
                            if (i & 2) {
                                await push(
                                    BigNumber.from(10).pow(11).mul(5),
                                    "USDC"
                                );
                                await sleep(this.governanceDelay);
                            } else {
                                await push(BigNumber.from(10).pow(21), "WETH");
                                await sleep(this.governanceDelay);
                            }
                        }

                        await sleep(this.governanceDelay);
                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .rebalance(restrictions, []);
                        if (!doFullRebalance) {
                            const tick = (await this.pool.slot0()).tick;
                            await checkState(tick);
                        }
                    }
                });
            });
        });
    }
);
