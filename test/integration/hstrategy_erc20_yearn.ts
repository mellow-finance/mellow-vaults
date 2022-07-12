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
import {
    MockHStrategy,
    StrategyParamsStruct,
    RatioParamsStruct,
} from "../types/MockHStrategy";
import Exceptions from "../library/Exceptions";
import { TickMath } from "@uniswap/v3-sdk";
import { RebalanceRestrictionsStruct } from "../types/HStrategy";
import { DomainPositionParamsStruct } from "../types/HStrategyHelper";

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
                        minUniV3RatioDeviation0D: BigNumber.from(10)
                            .pow(7)
                            .mul(5),
                        minUniV3RatioDeviation1D: BigNumber.from(10)
                            .pow(7)
                            .mul(5),
                        minMoneyRatioDeviation0D: BigNumber.from(10)
                            .pow(7)
                            .mul(5),
                        minMoneyRatioDeviation1D: BigNumber.from(10)
                            .pow(7)
                            .mul(5),
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
                        await withSigner(
                            this.subject.address,
                            async (signer) => {
                                await this.positionManager
                                    .connect(signer)
                                    .functions[
                                        "safeTransferFrom(address,address,uint256)"
                                    ](
                                        signer.address,
                                        this.uniV3Vault.address,
                                        tokenId
                                    );
                            }
                        );
                    };

                    this.getPositionParams = async () => {
                        const strategyParams =
                            await this.subject.strategyParams();
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

        describe.only("#rebalance", () => {
            const getPriceX96 = (tick: number) => {
                return this.getSqrtRatioAtTick(tick).pow(2).div(Q96);
            };

            it("`tvl chanages only on fees`", async () => {
                const centralTick = await getAverageTick();
                const globalLowerTick =
                    centralTick - 6000 - (centralTick % 600);
                const globalUpperTick =
                    centralTick + 6000 - (centralTick % 600);
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
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .updateRatioParams({
                        ...ratioParams,
                        minUniV3RatioDeviation0D: 0,
                        minUniV3RatioDeviation1D: 0,
                        minMoneyRatioDeviation0D: 0,
                        minMoneyRatioDeviation1D: 0,
                    } as RatioParamsStruct);
                await sleep(this.governanceDelay);
                const tvlBefore = (await this.erc20RootVault.tvl())
                    .minTokenAmounts;
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
                    const erc20Tvl = (await this.erc20Vault.tvl())
                        .minTokenAmounts;
                    const moneyTvl = (await this.yearnVault.tvl())
                        .minTokenAmounts;
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
                    const uniV3Tvl =
                        await this.uniV3Vault.liquidityToTokenAmounts(
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

                    const totalCapital = totalToken0.add(
                        totalToken1.mul(Q96).div(averagePriceX96)
                    );

                    const xCapital = totalCapital.mul(wxD).div(DENOMINATOR);
                    const yCapital = totalCapital
                        .mul(wyD)
                        .div(DENOMINATOR)
                        .mul(averagePriceX96)
                        .div(Q96);

                    const uniV3Capital = totalCapital
                        .mul(wUniD)
                        .div(DENOMINATOR);

                    const expectedErc20Token0 = xCapital
                        .mul(erc20MoneyRatioD)
                        .div(DENOMINATOR);
                    const expectedErc20Token1 = yCapital
                        .mul(erc20MoneyRatioD)
                        .div(DENOMINATOR);

                    const expectedMoneyToken0 =
                        xCapital.sub(expectedErc20Token0);
                    const expectedMoneyToken1 =
                        yCapital.sub(expectedErc20Token1);

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
                        const position = await this.positionManager.positions(
                            nft
                        );
                        const lowerPrice = getPriceX96(position.tickLower);
                        const upperPrice = getPriceX96(position.tickUpper);

                        if (
                            lowerPrice.lte(spotPrice) &&
                            upperPrice.gte(spotPrice) &&
                            lowerPrice.lte(averagePrice) &&
                            upperPrice.gte(averagePrice)
                        ) {
                            await this.subject
                                .connect(this.mStrategyAdmin)
                                .tokenRebalance(restrictions, []);
                        } else {
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
                const tvlAfter = (await this.erc20RootVault.tvl())
                    .minTokenAmounts;
                const capitalAfter = tvlAfter[0].add(
                    tvlAfter[1].mul(Q96).div(await getSpotPriceX96())
                );

                expect(totalCapital.mul(110).div(100).gte(capitalAfter)).to.be
                    .true;
                expect(capitalAfter.mul(110).div(100).gte(totalCapital)).to.be
                    .true;
            });
        });
    }
);
