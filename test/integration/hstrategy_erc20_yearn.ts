import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    randomAddress,
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
    IYearnProtocolVault,
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
import { expect } from "chai";

import { MockHStrategy, StrategyParamsStruct } from "../types/MockHStrategy";
import { RebalanceRestrictionsStruct } from "../types/HStrategy";
import { DomainPositionParamsStruct } from "../types/HStrategyHelper";
import { randomInt } from "crypto";
import exp from "constants";
import { resourceLimits } from "worker_threads";
import { TickMath } from "@uniswap/v3-sdk";

const DENOMINATOR = BigNumber.from(10).pow(9);
const Q96 = BigNumber.from(2).pow(96);

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

type StrategyState = {
    spotTick: BigNumber;
    averageTick: BigNumber;
    erc20Token0: BigNumber;
    erc20Token1: BigNumber;
    moneyToken0: BigNumber;
    moneyToken1: BigNumber;
    uniV3Token0: BigNumber;
    uniV3Token1: BigNumber;
};

type RebalanceResult = {
    revertedWith: string;
    erc20Token0: BigNumber;
    erc20Token1: BigNumber;
    moneyToken0: BigNumber;
    moneyToken1: BigNumber;
    uniV3Token0: BigNumber;
    uniV3Token1: BigNumber;
};

type DeployOptions = {};

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
            {
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .updateStrategyParams({
                        ...this.strategyParams,
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
            }

            var restrictions = {
                pulledOnUniV3Vault: [0, 0],
                pulledOnMoneyVault: [0, 0],
                pulledFromMoneyVault: [0, 0],
                swappedAmounts: [0, 0],
                burnedAmounts: [0, 0],
                deadline: ethers.constants.MaxUint256,
            } as RebalanceRestrictionsStruct;

            var STEPS = 100;
            var STEP = 0;
            var currentState: StrategyState;
            var expectedState: RebalanceResult;

            var lastTick = -1 * 10 ** 7;

            const changeCapital = async () => {
                if (STEP < STEPS / 10 || Math.random() > 0.5) {
                    const amount = BigNumber.from(10).pow(18);
                    const usdcRatio = BigNumber.from(
                        randomInt(
                            DENOMINATOR.div(100).toNumber(),
                            DENOMINATOR.div(5).toNumber()
                        )
                    );
                    const wethRatio = BigNumber.from(
                        randomInt(
                            DENOMINATOR.div(100).toNumber(),
                            DENOMINATOR.div(5).toNumber()
                        )
                    );
                    const usdcAmount = amount.mul(usdcRatio).div(DENOMINATOR);
                    const wethAmount = amount.mul(wethRatio).div(DENOMINATOR);
                    await mint("USDC", this.deployer.address, usdcAmount);
                    await mint("WETH", this.deployer.address, wethAmount);
                    await this.erc20RootVault.deposit(
                        [usdcAmount, wethAmount],
                        0,
                        []
                    );
                }
                {
                    const totalSupply = await this.erc20RootVault.totalSupply();
                    const lpAmonut = totalSupply
                        .mul(randomInt(0, DENOMINATOR.div(2).toNumber()))
                        .div(DENOMINATOR);
                    await this.erc20RootVault.withdraw(
                        ethers.constants.AddressZero,
                        lpAmonut,
                        [0, 0],
                        [[], []]
                    );
                }
            };

            const changePrice = async () => {
                if (STEP < STEPS / 2) {
                    await push(BigNumber.from(10).pow(11), "USDC");
                } else {
                    await push(BigNumber.from(10).pow(20), "WETH");
                }
                await sleep(this.governanceDelay);
            };

            const recalculateCurrentState = async () => {
                const { minTokenAmounts: erc20Tvl } =
                    await this.erc20Vault.tvl();
                const { minTokenAmounts: moneyTvl } =
                    await this.yearnVault.tvl();
                const nft = await this.uniV3Vault.nft();
                const position = await this.positionManager.positions(nft);
                const uniV3Tvl = await this.uniV3Vault.liquidityToTokenAmounts(
                    position.liquidity
                );
                const priceInfo =
                    await this.uniV3Helper.getAverageTickAndSqrtSpotPrice(
                        await this.subject.pool(),
                        this.strategyParams.oracleObservationDelta
                    );
                currentState = {
                    spotTick: position.tick,
                    averageTick: BigNumber.from(priceInfo.averageTick),
                    erc20Token0: erc20Tvl[0],
                    erc20Token1: erc20Tvl[1],
                    moneyToken0: moneyTvl[0],
                    moneyToken1: moneyTvl[1],
                    uniV3Token0: uniV3Tvl[0],
                    uniV3Token1: uniV3Tvl[1],
                } as StrategyState;
            };

            const updateParameters = async () => {
                var averageTick = currentState.spotTick.toNumber();
                averageTick = averageTick - (averageTick % 900);

                var globalLowerTick = averageTick - 900 * 20;
                var globalUpperTick = averageTick + 900 * 20;
                var erc20MoneyRatioD = randomInt(5 * 10 ** 7, 10 * 10 ** 7);

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .updateStrategyParams({
                        ...this.strategyParams,
                        globalLowerTick: globalLowerTick,
                        globalUpperTick: globalUpperTick,
                        erc20MoneyRatioD: erc20MoneyRatioD,
                    });
            };

            const getSqrtTickRatio = (tick: BigNumber) => {
                return BigNumber.from(
                    TickMath.getSqrtRatioAtTick(tick.toNumber()).toString()
                );
            };

            const getCapital = (
                tick: BigNumber,
                token0: BigNumber,
                token1: BigNumber
            ) => {
                return token0.add(
                    token1.mul(Q96).div(getSqrtTickRatio(tick).pow(2).div(Q96))
                );
            };

            const expectedStateAfterRebalance = async () => {
                const capital = getCapital(
                    currentState.averageTick,
                    currentState.erc20Token0,
                    currentState.erc20Token1
                )
                    .add(
                        getCapital(
                            currentState.averageTick,
                            currentState.moneyToken0,
                            currentState.moneyToken1
                        )
                    )
                    .add(
                        getCapital(
                            currentState.spotTick,
                            currentState.uniV3Token0,
                            currentState.uniV3Token1
                        )
                    );

                // calculate expected ratios
                // calculate expected amounts
            };

            const rebalanceAndCompareResults = async () => {
                if (expectedState.revertedWith != "") {
                    await expect(
                        this.subject
                            .connect(this.mStrategyAdmin)
                            .rebalance(restrictions, [])
                    ).to.be.revertedWith(expectedState.revertedWith);
                } else {
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .rebalance(restrictions, []);
                    const stateBeforeRebalance = currentState;
                    await recalculateCurrentState();
                    // check with some delta
                    expect(stateBeforeRebalance.erc20Token0).to.be.eq(
                        expectedState.erc20Token0
                    );
                    expect(stateBeforeRebalance.erc20Token1).to.be.eq(
                        expectedState.erc20Token1
                    );
                    expect(stateBeforeRebalance.uniV3Token0).to.be.eq(
                        expectedState.uniV3Token0
                    );
                    expect(stateBeforeRebalance.uniV3Token1).to.be.eq(
                        expectedState.uniV3Token1
                    );
                    expect(stateBeforeRebalance.moneyToken0).to.be.eq(
                        expectedState.moneyToken0
                    );
                    expect(stateBeforeRebalance.moneyToken1).to.be.eq(
                        expectedState.moneyToken1
                    );
                }
                lastTick = await this.positionManager.positions(
                    await this.uniV3Vault.uniV3Nft()
                ).tick;
            };

            while (STEP < STEPS) {
                await changeCapital();
                await changePrice();
                await recalculateCurrentState();
                await updateParameters();
                await expectedStateAfterRebalance();
                await rebalanceAndCompareResults();
            }
        });
    });
});
