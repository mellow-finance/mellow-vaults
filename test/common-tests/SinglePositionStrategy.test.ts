import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, sleep } from "../library/Helpers";
import { contract } from "../library/setup";
import {
    ERC20RootVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Vault,
    ISwapRouter as SwapRouterInterface,
    SinglePositionStrategy,
} from "../types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    setupVault,
    combineVaults,
    TRANSACTION_GAS_LIMITS,
} from "../../deploy/0000_utils";
import { Contract } from "@ethersproject/contracts";
import { TickMath } from "@uniswap/v3-sdk";

import {
    ImmutableParamsStruct,
    MutableParamsStruct,
} from "../types/SinglePositionStrategy";
import { expect } from "chai";

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault500: UniV3Vault;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    deployerWethAmount: BigNumber;
    deployerUsdcAmount: BigNumber;
    deployerDaiAmount: BigNumber;
    swapRouter: SwapRouterInterface;
    params: any;
};

type DeployOptions = {};

const DENOMINATOR = BigNumber.from(10).pow(9);
const Q96 = BigNumber.from(2).pow(96);

contract<SinglePositionStrategy, DeployOptions, CustomContext>(
    "SinglePositionStrategy",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;
                    const { deploy } = deployments;
                    const tokens = [this.dai.address, this.weth.address]
                        .map((t) => t.toLowerCase())
                        .sort();

                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let erc20VaultNft = startNft;
                    let uniV3Vault500Nft = startNft + 1;
                    let erc20RootVaultNft = startNft + 2;

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
                            delayedStrategyParams: [2],
                        }
                    );

                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );

                    const uniV3Vault500 = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        uniV3Vault500Nft
                    );

                    this.erc20Vault = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    );

                    this.uniV3Vault500 = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault500
                    );

                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    this.swapRouter = await ethers.getContractAt(
                        ISwapRouter,
                        uniswapV3Router
                    );

                    const mutableParams = {
                        feeTierOfPoolOfAuxiliaryAnd0Tokens: 100,
                        feeTierOfPoolOfAuxiliaryAnd1Tokens: 500,
                        priceImpactD6: 0,
                        auxiliaryToken: this.usdc.address,
                        intervalWidth: 600,
                        tickNeighborhood: 10,
                        maxDeviationForVaultPool: 100,
                        maxDeviationForPoolOfAuxiliaryAnd0Tokens: 100,
                        maxDeviationForPoolOfAuxiliaryAnd1Tokens: 100,
                        timespanForAverageTick: 60,
                        amount0Desired: 10 ** 9,
                        amount1Desired: 10 ** 9,
                        swapSlippageD: 7 * 10 ** 8,
                        minSwapAmounts: [
                            BigNumber.from(10).pow(0),
                            BigNumber.from(10).pow(0),
                        ],
                    } as MutableParamsStruct;

                    let immutableParams = {
                        router: this.swapRouter.address,
                        tokens: tokens,
                        erc20Vault: this.erc20Vault.address,
                        uniV3Vault: this.uniV3Vault500.address,
                    } as ImmutableParamsStruct;

                    for (var poolData of [
                        [
                            tokens[0],
                            mutableParams.auxiliaryToken,
                            mutableParams.feeTierOfPoolOfAuxiliaryAnd0Tokens,
                        ],
                        [
                            tokens[1],
                            mutableParams.auxiliaryToken,
                            mutableParams.feeTierOfPoolOfAuxiliaryAnd1Tokens,
                        ],
                    ]) {
                        const factory = await ethers.getContractAt(
                            "IUniswapV3Factory",
                            await this.positionManager.factory()
                        );
                        const swapPool = await factory.getPool(
                            poolData[0],
                            poolData[1],
                            poolData[2]
                        );
                        await this.protocolGovernance
                            .connect(this.admin)
                            .stagePermissionGrants(swapPool, [4]);
                    }

                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();

                    const params = [
                        immutableParams,
                        mutableParams,
                        this.mStrategyAdmin.address,
                    ];

                    const { address: strategyAddress } = await deploy(
                        "SinglePositionStrategy",
                        {
                            from: this.deployer.address,
                            contract: "SinglePositionStrategy",
                            args: [uniswapV3PositionManager],
                            log: true,
                            autoMine: true,
                            ...TRANSACTION_GAS_LIMITS,
                        }
                    );

                    this.subject = await ethers.getContractAt(
                        "SinglePositionStrategy",
                        strategyAddress
                    );

                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [erc20VaultNft, uniV3Vault500Nft],
                        strategyAddress,
                        this.deployer.address,
                        {
                            limits: [
                                ethers.constants.MaxUint256,
                                ethers.constants.MaxUint256,
                            ],
                            strategyPerformanceTreasuryAddress:
                                ethers.constants.AddressZero,
                            tokenLimitPerAddress: ethers.constants.MaxUint256,
                            tokenLimit: ethers.constants.MaxUint256,
                            managementFee: BigNumber.from(0),
                            performanceFee: BigNumber.from(0),
                        }
                    );

                    await this.subject.initialize(
                        immutableParams,
                        this.mStrategyAdmin.address
                    );
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .updateMutableParams(mutableParams);

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

                    let delayedStrategyParams =
                        await this.erc20RootVaultGovernance.delayedStrategyParams(
                            erc20RootVaultNft
                        );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedStrategyParams(erc20RootVaultNft, {
                            ...delayedStrategyParams,
                            depositCallbackAddress: strategyAddress,
                        });

                    await sleep(this.governanceDelay);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedStrategyParams(erc20RootVaultNft);

                    await this.erc20RootVault
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    for (let addr of [
                        strategyAddress,
                        this.erc20RootVault.address,
                        this.swapRouter.address,
                    ]) {
                        await this.weth.approve(
                            addr,
                            ethers.constants.MaxUint256
                        );
                        await this.dai.approve(
                            addr,
                            ethers.constants.MaxUint256
                        );
                        await this.usdc.approve(
                            addr,
                            ethers.constants.MaxUint256
                        );
                    }

                    await mint(
                        "WETH",
                        this.deployer.address,
                        BigNumber.from(10).pow(18).mul(1000)
                    );

                    await mint(
                        "USDC",
                        this.deployer.address,
                        BigNumber.from(10)
                            .pow(6)
                            .mul(10 ** 9)
                    );

                    await this.swapRouter.exactInputSingle({
                        tokenIn: this.usdc.address,
                        tokenOut: this.weth.address,
                        fee: 3000,
                        recipient: this.deployer.address,
                        deadline: ethers.constants.MaxUint256,
                        amountIn: BigNumber.from(10)
                            .pow(6)
                            .mul(10 ** 8),
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0,
                    });

                    await this.swapRouter.exactInputSingle({
                        tokenIn: this.weth.address,
                        tokenOut: this.dai.address,
                        fee: 3000,
                        recipient: this.deployer.address,
                        deadline: ethers.constants.MaxUint256,
                        amountIn: BigNumber.from(10).pow(18).mul(500),
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0,
                    });

                    this.deployerWethAmount = await this.weth.balanceOf(
                        this.deployer.address
                    );
                    this.deployerUsdcAmount = await this.usdc.balanceOf(
                        this.deployer.address
                    );
                    this.deployerDaiAmount = await this.dai.balanceOf(
                        this.deployer.address
                    );

                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    this.pullExistentials =
                        await this.erc20Vault.pullExistentials();

                    await this.dai
                        .connect(this.deployer)
                        .transfer(
                            this.subject.address,
                            this.pullExistentials[0].mul(100)
                        );
                    await this.weth
                        .connect(this.deployer)
                        .transfer(
                            this.subject.address,
                            this.pullExistentials[1].mul(100)
                        );

                    this.getSqrtRatioAtTick = (tick: number) => {
                        return BigNumber.from(
                            TickMath.getSqrtRatioAtTick(tick).toString()
                        );
                    };

                    const factory = await ethers.getContractAt(
                        "IUniswapV3Factory",
                        await this.positionManager.factory()
                    );

                    this.poolUsdcWeth = await ethers.getContractAt(
                        "IUniswapV3Pool",
                        await factory.getPool(
                            this.usdc.address,
                            this.weth.address,
                            500
                        )
                    );
                    this.poolDaiWeth = await ethers.getContractAt(
                        "IUniswapV3Pool",
                        await factory.getPool(
                            this.dai.address,
                            this.weth.address,
                            500
                        )
                    );
                    this.poolUsdcDai = await ethers.getContractAt(
                        "IUniswapV3Pool",
                        await factory.getPool(
                            this.usdc.address,
                            this.dai.address,
                            100
                        )
                    );

                    this.stabilizePrices = async () => {
                        // dai - usdc = 1 usdc wei = 1e12 dai wei
                        {
                            let targetDaiUsdcTick = -276324; // log(1e-12) / log(1.0001)
                            let denominator = 1;
                            for (var i = 0; i < 20; i++) {
                                let currentTick = (
                                    await this.poolUsdcDai.slot0()
                                ).tick;
                                if (currentTick == targetDaiUsdcTick) break;
                                if (currentTick > targetDaiUsdcTick) {
                                    await this.swapRouter.exactInputSingle({
                                        tokenIn: this.usdc.address,
                                        tokenOut: this.dai.address,
                                        fee: 100,
                                        recipient: this.deployer.address,
                                        deadline: ethers.constants.MaxUint256,
                                        amountIn: BigNumber.from(10)
                                            .pow(6)
                                            .mul(BigNumber.from(500 * 100))
                                            .div(denominator),
                                        amountOutMinimum: 0,
                                        sqrtPriceLimitX96: 0,
                                    });
                                } else {
                                    await this.swapRouter.exactInputSingle({
                                        tokenIn: this.dai.address,
                                        tokenOut: this.usdc.address,
                                        fee: 100,
                                        recipient: this.deployer.address,
                                        deadline: ethers.constants.MaxUint256,
                                        amountIn: BigNumber.from(10)
                                            .pow(18)
                                            .mul(BigNumber.from(500 * 100))
                                            .div(denominator),
                                        amountOutMinimum: 0,
                                        sqrtPriceLimitX96: 0,
                                    });
                                }
                                denominator *= 2;
                            }
                        }

                        // usdc - weth
                        // daiToWeth tick + 276324
                        {
                            let targetUsdcWethTick =
                                (await this.poolDaiWeth.slot0()).tick + 276324;
                            let divider = 1;
                            for (var i = 0; i < 30; i++) {
                                let currentTick = (
                                    await this.poolUsdcWeth.slot0()
                                ).tick;
                                if (currentTick == targetUsdcWethTick) break;
                                if (currentTick > targetUsdcWethTick) {
                                    await this.swapRouter.exactInputSingle({
                                        tokenIn: this.usdc.address,
                                        tokenOut: this.weth.address,
                                        fee: 500,
                                        recipient: this.deployer.address,
                                        deadline: ethers.constants.MaxUint256,
                                        amountIn: BigNumber.from(10)
                                            .pow(6)
                                            .mul(BigNumber.from(10000000))
                                            .div(divider),
                                        amountOutMinimum: 0,
                                        sqrtPriceLimitX96: 0,
                                    });
                                } else {
                                    await this.swapRouter.exactInputSingle({
                                        tokenIn: this.weth.address,
                                        tokenOut: this.usdc.address,
                                        fee: 500,
                                        recipient: this.deployer.address,
                                        deadline: ethers.constants.MaxUint256,
                                        amountIn: BigNumber.from(10)
                                            .pow(18)
                                            .mul(BigNumber.from(10000))
                                            .div(divider),
                                        amountOutMinimum: 0,
                                        sqrtPriceLimitX96: 0,
                                    });
                                }
                                divider *= 2;
                            }
                        }
                    };

                    this.movePrices = async (index: number) => {
                        if (index < 2) {
                            await this.swapRouter.exactInputSingle({
                                tokenIn: this.dai.address,
                                tokenOut: this.weth.address,
                                fee: 500,
                                recipient: this.deployer.address,
                                deadline: ethers.constants.MaxUint256,
                                amountIn: BigNumber.from(10)
                                    .pow(18)
                                    .mul(100000),
                                amountOutMinimum: 0,
                                sqrtPriceLimitX96: 0,
                            });
                        } else {
                            await this.swapRouter.exactInputSingle({
                                tokenIn: this.weth.address,
                                tokenOut: this.dai.address,
                                fee: 500,
                                recipient: this.deployer.address,
                                deadline: ethers.constants.MaxUint256,
                                amountIn: BigNumber.from(10).pow(18).mul(100),
                                amountOutMinimum: 0,
                                sqrtPriceLimitX96: 0,
                            });
                        }
                    };

                    await this.protocolGovernance
                        .connect(this.admin)
                        .stageUnitPrice(
                            this.dai.address,
                            BigNumber.from(10).pow(18)
                        );
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitUnitPrice(this.dai.address);
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#constructor", () => {
            it("creates contract", async () => {
                expect(this.subject.address).not.eq(
                    ethers.constants.AddressZero
                );
            });
        });

        describe("#rebalance", () => {
            const updateIntervalWidth = async (width: number) => {
                let mutableParams = await this.subject.mutableParams();
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .updateMutableParams({
                        ...mutableParams,
                        minSwapAmounts: [
                            BigNumber.from(10).pow(0),
                            BigNumber.from(10).pow(0),
                        ],
                        intervalWidth: width,
                    });
            };

            it("works correctly", async () => {
                await this.erc20RootVault
                    .connect(this.deployer)
                    .deposit(
                        [
                            this.pullExistentials[0].mul(13000),
                            this.pullExistentials[1].mul(10),
                        ],
                        0,
                        []
                    );

                await this.erc20RootVault
                    .connect(this.deployer)
                    .deposit(
                        [
                            BigNumber.from(10).pow(18).mul(1300),
                            BigNumber.from(10).pow(18).mul(1),
                        ],
                        0,
                        []
                    );
                const pool = await ethers.getContractAt(
                    "IUniswapV3Pool",
                    await this.uniV3Vault500.pool()
                );

                for (let intervalWidth of [20, 200, 2000, 20000]) {
                    await updateIntervalWidth(intervalWidth);
                    for (let i = 0; i < 4; i++) {
                        if (i % 2 == 0) {
                            const amount0 = BigNumber.from(10)
                                .pow(18)
                                .mul(1300);
                            const amount1 = BigNumber.from(10)
                                .pow(18)
                                .mul(1300);

                            await this.erc20RootVault
                                .connect(this.deployer)
                                .deposit([amount0, amount1], 0, []);
                        }
                        await this.movePrices(i);
                        await this.stabilizePrices();
                        await sleep(this.governanceDelay);

                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .rebalance(ethers.constants.MaxUint256);

                        const erc20 = (await this.erc20Vault.tvl())
                            .minTokenAmounts;
                        const total = (await this.erc20RootVault.tvl())
                            .minTokenAmounts;

                        const { sqrtPriceX96 } = await pool.slot0();
                        const priceX96 = sqrtPriceX96
                            .mul(sqrtPriceX96)
                            .div(Q96);
                        const totalCapital = total[0].add(
                            total[1].mul(Q96).div(priceX96)
                        );
                        const erc20Capital = erc20[0].add(
                            erc20[1].mul(Q96).div(priceX96)
                        );

                        const currentERC20RatioD =
                            DENOMINATOR.mul(erc20Capital).div(totalCapital);
                        expect(currentERC20RatioD.lte(50000)).to.be.true; // at most = 0.005% on ERC20Vault

                        if (i % 2 == 1) {
                            const balance = await this.erc20RootVault.balanceOf(
                                this.deployer.address
                            );
                            await this.erc20RootVault
                                .connect(this.deployer)
                                .withdraw(
                                    this.deployer.address,
                                    balance.div(2),
                                    [0, 0],
                                    [[], []]
                                );
                        }
                    }
                }
            });
        });
    }
);
