import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, sleep } from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Vault,
    ISwapRouter as SwapRouterInterface,
    SinglePositionStrategy,
    SinglePositionRebalancer,
} from "./types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    setupVault,
    combineVaults,
    TRANSACTION_GAS_LIMITS,
} from "../deploy/0000_utils";
import { Contract } from "@ethersproject/contracts";
import { TickMath } from "@uniswap/v3-sdk";

import {
    ImmutableParamsStruct,
    IntervalStruct,
    MutableParamsStruct,
    RestrictionsStruct,
} from "./types/SinglePositionStrategy";
import { expect } from "chai";

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault500: UniV3Vault;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    deployerWethAmount: BigNumber;
    deployerUsdcAmount: BigNumber;
    swapRouter: SwapRouterInterface;
    params: any;
    rebalancer: SinglePositionRebalancer;
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
                    const { deploy, get } = deployments;
                    const tokens = [this.weth.address, this.usdc.address]
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
                            delayedProtocolPerVaultParams: [2],
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

                    const { address: rebalancerAddress } = await deploy(
                        "SinglePositionRebalancer",
                        {
                            from: this.deployer.address,
                            contract: "SinglePositionRebalancer",
                            args: [this.positionManager.address],
                            log: true,
                            autoMine: true,
                            ...TRANSACTION_GAS_LIMITS,
                        }
                    );

                    const { address: baseStrategyAddress } = await deploy(
                        "SinglePositionStrategy",
                        {
                            from: this.deployer.address,
                            contract: "SinglePositionStrategy",
                            args: [],
                            log: true,
                            autoMine: true,
                            ...TRANSACTION_GAS_LIMITS,
                        }
                    );

                    const baseStrategy = await ethers.getContractAt(
                        "SinglePositionStrategy",
                        baseStrategyAddress
                    );

                    this.tickSpacing = 60;
                    const mutableParams = {
                        maxTickDeviation: 100,
                        tickSpacing: this.tickSpacing,
                        swapFee: 500,
                        averageTickTimespan: 60,
                        amount0ForMint: 10 ** 9,
                        amount1ForMint: 10 ** 9,
                        erc20CapitalRatioD: 10 ** 7,
                        swapSlippageD: 10 ** 7,
                    } as MutableParamsStruct;

                    let immutableParams = {
                        token0: tokens[0],
                        token1: tokens[1],
                        router: this.swapRouter.address,
                        erc20Vault: this.erc20Vault.address,
                        uniV3Vault: this.uniV3Vault500.address,
                        rebalancer: rebalancerAddress,
                    } as ImmutableParamsStruct;

                    const params = [
                        immutableParams,
                        mutableParams,
                        this.mStrategyAdmin.address,
                    ];
                    const newStrategyAddress =
                        await baseStrategy.callStatic.createStrategy(...params);
                    await baseStrategy.createStrategy(...params);
                    this.subject = await ethers.getContractAt(
                        "SinglePositionStrategy",
                        newStrategyAddress
                    );

                    immutableParams = await this.subject.immutableParams();
                    this.rebalancer = await ethers.getContractAt(
                        "SinglePositionRebalancer",
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

                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [erc20VaultNft, uniV3Vault500Nft],
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
                                BigNumber.from(10).pow(10).div(11),
                                BigNumber.from(10).pow(18).div(11),
                            ],
                            0,
                            []
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

        describe("#constructor", () => {
            it("creates contract", async () => {
                expect(this.subject.address).not.eq(
                    ethers.constants.AddressZero
                );
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
                    fee: 500,
                    recipient: this.deployer.address,
                    deadline: ethers.constants.MaxUint256,
                    amountIn: delta.div(n),
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0,
                });
            }
        };

        describe("#rebalance", () => {
            it("works correctly", async () => {
                const pool = await ethers.getContractAt(
                    "IUniswapV3Pool",
                    await this.uniV3Vault500.pool()
                );
                for (var i = 0; i < 10; i++) {
                    await this.erc20RootVault
                        .connect(this.deployer)
                        .deposit(
                            [
                                BigNumber.from(10).pow(10).div(11),
                                BigNumber.from(10).pow(18).div(11),
                            ],
                            0,
                            []
                        );

                    const { sqrtPriceX96, tick } = await pool.slot0();
                    const centerTick = tick - (tick % this.tickSpacing);
                    const toLeft = Math.round(Math.random() * 10) + 1;
                    const toRight = Math.round(Math.random() * 10) + 1;
                    const interval = {
                        lowerTick: centerTick - toLeft * this.tickSpacing,
                        upperTick: centerTick + toRight * this.tickSpacing,
                    } as IntervalStruct;

                    await this.subject.connect(this.mStrategyAdmin).rebalance({
                        newInterval: interval,
                        swappedAmounts: [0, 0],
                        drainedAmounts: [0, 0],
                        pulledToUniV3: [0, 0],
                        pulledFromUniV3: [0, 0],
                        deadline: ethers.constants.MaxUint256,
                    } as RestrictionsStruct);

                    const mutableParams = await this.subject.mutableParams();
                    const tvls = await this.rebalancer.callStatic.getTvls(
                        await this.subject.getData(
                            await this.subject.immutableParams()
                        )
                    );

                    const priceX96 = sqrtPriceX96.mul(sqrtPriceX96).div(Q96);
                    const totalCapital = tvls.total[0].add(
                        tvls.total[1].mul(Q96).div(priceX96)
                    );
                    const erc20Capital = tvls.erc20[0].add(
                        tvls.erc20[1].mul(Q96).div(priceX96)
                    );
                    const uniV3Capital = tvls.uniV3[0].add(
                        tvls.uniV3[1].mul(Q96).div(priceX96)
                    );
                    const expectedErc20Capital = totalCapital
                        .mul(mutableParams.erc20CapitalRatioD)
                        .div(DENOMINATOR);
                    const expectedUniV3Capital = totalCapital
                        .mul(DENOMINATOR.sub(mutableParams.erc20CapitalRatioD))
                        .div(DENOMINATOR);

                    const currentERC20RatioD =
                        DENOMINATOR.mul(erc20Capital).div(totalCapital);
                    const currentUniV3RatioD =
                        DENOMINATOR.mul(uniV3Capital).div(totalCapital);
                    const expectedERC20RatioD =
                        DENOMINATOR.mul(expectedErc20Capital).div(totalCapital);
                    const expectedUniV3RatioD =
                        DENOMINATOR.mul(expectedUniV3Capital).div(totalCapital);

                    expect(currentERC20RatioD.toNumber()).to.be.closeTo(
                        expectedERC20RatioD.toNumber(),
                        DENOMINATOR.div(100).toNumber()
                    );
                    expect(currentUniV3RatioD.toNumber()).to.be.closeTo(
                        expectedUniV3RatioD.toNumber(),
                        DENOMINATOR.div(100).toNumber()
                    );

                    if (Math.random() > 0.5) {
                        await push(BigNumber.from(10).pow(12), "USDC");
                    } else {
                        await push(BigNumber.from(10).pow(21), "WETH");
                    }
                    await sleep(this.governanceDelay);
                }
            });
        });
    }
);
