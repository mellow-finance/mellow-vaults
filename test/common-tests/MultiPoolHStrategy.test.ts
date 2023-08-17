import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, sleep } from "../library/Helpers";
import { contract } from "../library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Vault,
    ISwapRouter as SwapRouterInterface,
    MultiPoolHStrategy,
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
import { TickMath } from "@uniswap/v3-sdk";
import { IUniswapV3Pool } from "../types/IUniswapV3Pool";
import {
    MultiPoolHStrategyRebalancer,
    StrategyDataStruct,
} from "../types/MultiPoolHStrategyRebalancer";
import {
    ImmutableParamsStruct,
    MutableParamsStruct,
    RestrictionsStruct,
} from "../types/MultiPoolHStrategy";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    uniV3Vault100: UniV3Vault;
    uniV3Vault500: UniV3Vault;
    uniV3Vault3000: UniV3Vault;
    uniV3Vault10000: UniV3Vault;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    deployerWethAmount: BigNumber;
    deployerUsdcAmount: BigNumber;
    swapRouter: SwapRouterInterface;
    params: any;
    firstPool: IUniswapV3Pool;
    rebalancer: MultiPoolHStrategyRebalancer;
};

type DeployOptions = {};

const DENOMINATOR = BigNumber.from(10).pow(9);
const Q96 = BigNumber.from(2).pow(96);

contract<MultiPoolHStrategy, DeployOptions, CustomContext>(
    "MultiPoolHStrategy",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;
                    const { deploy, get } = deployments;
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
                    let uniV3Vault500Nft = startNft + 2;
                    let uniV3Vault3000Nft = startNft + 3;
                    let uniV3Vault10000Nft = startNft + 4;
                    let erc20RootVaultNft = startNft + 5;
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

                    const { uniswapV3PositionManager, uniswapV3Router } =
                        await getNamedAccounts();
                    await deploy("UniV3Helper", {
                        from: this.deployer.address,
                        contract: "UniV3Helper",
                        args: [uniswapV3PositionManager],
                        log: true,
                        autoMine: true,
                        ...TRANSACTION_GAS_LIMITS,
                    });

                    this.uniV3Helper = await ethers.getContract("UniV3Helper");

                    await setupVault(
                        hre,
                        uniV3Vault500Nft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                500,
                                this.uniV3Helper.address,
                            ],
                        }
                    );
                    await setupVault(
                        hre,
                        uniV3Vault3000Nft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                3000,
                                this.uniV3Helper.address,
                            ],
                        }
                    );

                    await setupVault(
                        hre,
                        uniV3Vault10000Nft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                10000,
                                this.uniV3Helper.address,
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

                    const uniV3Vault500 = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        uniV3Vault500Nft
                    );

                    const uniV3Vault3000 = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        uniV3Vault3000Nft
                    );

                    const uniV3Vault10000 = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        uniV3Vault10000Nft
                    );

                    this.erc20Vault = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    );
                    this.yearnVault = await ethers.getContractAt(
                        "YearnVault",
                        yearnVault
                    );

                    this.uniV3Vault500 = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault500
                    );

                    this.uniV3Vault3000 = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault3000
                    );

                    this.uniV3Vault10000 = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault10000
                    );

                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    this.swapRouter = await ethers.getContractAt(
                        ISwapRouter,
                        uniswapV3Router
                    );

                    const { address: rebalancerAddress } = await deploy(
                        "MultiPoolHStrategyRebalancer",
                        {
                            from: this.deployer.address,
                            contract: "MultiPoolHStrategyRebalancer",
                            args: [this.positionManager.address],
                            log: true,
                            autoMine: true,
                            ...TRANSACTION_GAS_LIMITS,
                        }
                    );

                    const { address: baseStrategyAddress } = await deploy(
                        "MultiPoolHStrategy",
                        {
                            from: this.deployer.address,
                            contract: "MultiPoolHStrategy",
                            args: [],
                            log: true,
                            autoMine: true,
                            ...TRANSACTION_GAS_LIMITS,
                        }
                    );

                    const baseStrategy = await ethers.getContractAt(
                        "MultiPoolHStrategy",
                        baseStrategyAddress
                    );
                    this.weights = [1, 1, 1];
                    this.firstPool = await ethers.getContractAt(
                        "IUniswapV3Pool",
                        await this.uniV3Vault500.pool()
                    );

                    this.uniV3Vaults = Array.from([
                        this.uniV3Vault500.address,
                        this.uniV3Vault3000.address,
                        this.uniV3Vault10000.address,
                    ]);

                    const mutableParams = {
                        halfOfShortInterval: 1800,
                        domainLowerTick: 190800,
                        domainUpperTick: 219600,
                        amount0ForMint: 10 ** 5,
                        amount1ForMint: 10 ** 9,
                        erc20CapitalRatioD: 5000000,
                        uniV3Weights: this.weights,
                        swapPool: this.firstPool.address,
                        maxTickDeviation: 100,
                        averageTickTimespan: 60,
                    } as MutableParamsStruct;

                    this.tickSpacing = 600;
                    const params = [
                        {
                            tokens: tokens,
                            erc20Vault: this.erc20Vault.address,
                            moneyVault: this.yearnVault.address,
                            router: this.swapRouter.address,
                            rebalancer: rebalancerAddress,
                            uniV3Vaults: this.uniV3Vaults,
                            tickSpacing: this.tickSpacing,
                        } as ImmutableParamsStruct,
                        mutableParams,
                        this.mStrategyAdmin.address,
                    ];
                    const newStrategyAddress =
                        await baseStrategy.callStatic.createStrategy(...params);
                    await baseStrategy.createStrategy(...params);
                    this.subject = await ethers.getContractAt(
                        "MultiPoolHStrategy",
                        newStrategyAddress
                    );

                    const immutableParams =
                        await this.subject.immutableParams();
                    this.rebalancer = await ethers.getContractAt(
                        "MultiPoolHStrategyRebalancer",
                        immutableParams.rebalancer
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

                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [
                            erc20VaultNft,
                            yearnVaultNft,
                            uniV3Vault500Nft,
                            uniV3Vault3000Nft,
                            uniV3Vault10000Nft,
                        ],
                        this.rebalancer.address,
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
                        this.rebalancer.address,
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

                    const pullExistentials =
                        await this.erc20Vault.pullExistentials();

                    await this.erc20RootVault
                        .connect(this.deployer)
                        .deposit(
                            [
                                pullExistentials[0].mul(10),
                                pullExistentials[1].mul(10),
                            ],
                            0,
                            []
                        );

                    await this.erc20RootVault
                        .connect(this.deployer)
                        .deposit(
                            [
                                BigNumber.from(10).pow(10),
                                BigNumber.from(10).pow(18),
                            ],
                            0,
                            []
                        );

                    await this.usdc
                        .connect(this.deployer)
                        .transfer(
                            this.subject.address,
                            pullExistentials[0].mul(10)
                        );
                    await this.weth
                        .connect(this.deployer)
                        .transfer(
                            this.subject.address,
                            pullExistentials[1].mul(10)
                        );

                    await this.usdc
                        .connect(this.deployer)
                        .transfer(
                            this.rebalancer.address,
                            pullExistentials[0].mul(10)
                        );
                    await this.weth
                        .connect(this.deployer)
                        .transfer(
                            this.rebalancer.address,
                            pullExistentials[1].mul(10)
                        );

                    this.getSqrtRatioAtTick = (tick: number) => {
                        return BigNumber.from(
                            TickMath.getSqrtRatioAtTick(tick).toString()
                        );
                    };

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#rebalance", () => {
            it("works correctly", async () => {
                const getData = async () => {
                    const immutableParams =
                        await this.subject.immutableParams();
                    const shortInterval = await this.subject.shortInterval();
                    const mutableParams = await this.subject.mutableParams();

                    const data = {
                        halfOfShortInterval: mutableParams.halfOfShortInterval,
                        domainLowerTick: mutableParams.domainLowerTick,
                        domainUpperTick: mutableParams.domainUpperTick,
                        shortLowerTick: shortInterval.lowerTick,
                        shortUpperTick: shortInterval.upperTick,
                        erc20Vault: this.erc20Vault.address,
                        moneyVault: this.yearnVault.address,
                        router: immutableParams.router,
                        amount0ForMint: mutableParams.amount0ForMint,
                        amount1ForMint: mutableParams.amount1ForMint,
                        erc20CapitalRatioD: mutableParams.erc20CapitalRatioD,
                        uniV3Weights: this.weights,
                        tokens: await this.erc20RootVault.vaultTokens(),
                        uniV3Vaults: this.uniV3Vaults,
                        swapPool: this.firstPool.address,
                        maxTickDeviation: 100,
                        averageTickTimespan: 60,
                    } as StrategyDataStruct;
                    return data;
                };

                const getTvls = async () => {
                    return await this.rebalancer.callStatic.getTvls(
                        await getData()
                    );
                };

                let emptyArrays = [];
                for (var i = 0; i < this.uniV3Vaults.length; i++) {
                    emptyArrays.push([0, 0]);
                }
                const { tick, sqrtPriceX96 } = await this.firstPool.slot0();
                const expectedNewShortInterval =
                    await this.rebalancer.calculateNewPosition(
                        await getData(),
                        tick
                    );

                await this.subject.connect(this.mStrategyAdmin).rebalance({
                    newShortLowerTick:
                        expectedNewShortInterval.newShortLowerTick,
                    newShortUpperTick:
                        expectedNewShortInterval.newShortUpperTick,
                    swappedAmounts: [0, 0],
                    drainedAmounts: emptyArrays,
                    pulledToUniV3: emptyArrays,
                    pulledFromUniV3: emptyArrays,
                    deadline: ethers.constants.MaxUint256,
                } as RestrictionsStruct);

                const sqrtC = sqrtPriceX96;
                const priceX96 = sqrtPriceX96
                    .pow(2)
                    .div(BigNumber.from(2).pow(96));

                const data = await getData();
                const tvls = await getTvls();

                const capital0 = tvls.total[0].add(
                    tvls.total[1].mul(Q96).div(priceX96)
                );

                const sqrtA = this.getSqrtRatioAtTick(data.shortLowerTick);
                const sqrtB = this.getSqrtRatioAtTick(data.shortUpperTick);
                const sqrtA0 = this.getSqrtRatioAtTick(data.domainLowerTick);
                const sqrtB0 = this.getSqrtRatioAtTick(data.domainUpperTick);

                const uniV3RatioD = DENOMINATOR.mul(
                    Q96.mul(2)
                        .sub(sqrtA.mul(Q96).div(sqrtC))
                        .sub(sqrtC.mul(Q96).div(sqrtB))
                ).div(
                    Q96.mul(2)
                        .sub(sqrtA0.mul(Q96).div(sqrtC))
                        .sub(sqrtC.mul(Q96).div(sqrtB0))
                );
                const token0RatioD = DENOMINATOR.mul(
                    Q96.mul(sqrtC).div(sqrtB).sub(Q96.mul(sqrtC).div(sqrtB0))
                ).div(
                    Q96.mul(2)
                        .sub(sqrtA0.mul(Q96).div(sqrtC))
                        .sub(sqrtC.mul(Q96).div(sqrtB0))
                );
                const token1RatioD = DENOMINATOR.mul(
                    Q96.mul(sqrtA).div(sqrtC).sub(Q96.mul(sqrtA0).div(sqrtC))
                ).div(
                    Q96.mul(2)
                        .sub(sqrtA0.mul(Q96).div(sqrtC))
                        .sub(sqrtC.mul(Q96).div(sqrtB0))
                );

                expect(
                    uniV3RatioD.add(token0RatioD).add(token1RatioD).toNumber()
                ).to.be.closeTo(DENOMINATOR.toNumber(), 1000);
                const currentUniV3Capital = tvls.totalUniV3[0].add(
                    tvls.totalUniV3[1].mul(Q96).div(priceX96)
                );

                const actualUniV3RatioD =
                    DENOMINATOR.mul(currentUniV3Capital).div(capital0);
                // up to 0.05% diff
                expect(actualUniV3RatioD.toNumber()).closeTo(
                    uniV3RatioD.toNumber(),
                    DENOMINATOR.div(10000).mul(5).toNumber()
                );

                const actualToken0Capital = tvls.erc20[0].add(tvls.money[0]);
                const actualToken1Capital = tvls.erc20[1]
                    .add(tvls.money[1])
                    .mul(Q96)
                    .div(priceX96);
                const actualToken0RatioD = actualToken0Capital
                    .mul(DENOMINATOR)
                    .div(capital0);
                const actualToken1RatioD = actualToken1Capital
                    .mul(DENOMINATOR)
                    .div(capital0);

                // up to 0.05% diff
                expect(actualToken0RatioD.toNumber()).closeTo(
                    token0RatioD.toNumber(),
                    DENOMINATOR.div(10000).mul(5).toNumber()
                );

                // up to 0.05% diff
                expect(actualToken1RatioD.toNumber()).closeTo(
                    token1RatioD.toNumber(),
                    DENOMINATOR.div(10000).mul(5).toNumber()
                );
            });
        });
    }
);
