import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, sleep } from "../library/Helpers";
import { contract } from "../library/setup";
import {
    ERC20RootVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Helper,
    UniV3Vault,
    ISwapRouter as SwapRouterInterface,
    PulseStrategyV2,
    PulseStrategyV2Helper,
    Mock1InchRouter,
} from "../types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";

import {
    setupVault,
    combineVaults,
    TRANSACTION_GAS_LIMITS,
} from "../../deploy/0000_utils";
import { Contract } from "@ethersproject/contracts";

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault: UniV3Vault;
    uniV3Helper: UniV3Helper;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    params: any;
    strategy: PulseStrategyV2;
    strategyHelper: PulseStrategyV2Helper;
    deployerWethAmount: BigNumber;
    mockRouter: Mock1InchRouter;
    deployerUsdcAmount: BigNumber;
    swapRouter: SwapRouterInterface;
};

type DeployOptions = {};

const DENOMINATOR = BigNumber.from(10).pow(9);
const Q96 = BigNumber.from(2).pow(96);

contract<PulseStrategyV2, DeployOptions, CustomContext>(
    "Integration__uni_v3_pulse_v2",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read, deploy } = deployments;
                    const tokens = [this.weth.address, this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();
                    this.tokens = [this.usdc, this.weth];
                    const { uniswapV3Router, uniswapV3PositionManager } =
                        await hre.getNamedAccounts();
                    /*
                     * Configure & deploy subvaults
                     */

                    this.swapRouter = await ethers.getContractAt(
                        ISwapRouter,
                        uniswapV3Router
                    );

                    await deploy("UniV3Helper", {
                        from: this.deployer.address,
                        contract: "UniV3Helper",
                        args: [uniswapV3PositionManager],
                        log: true,
                        autoMine: true,
                        ...TRANSACTION_GAS_LIMITS,
                    });
                    {
                        const { address: mockRouterAddress } = await deploy(
                            "Mock1InchRouter",
                            {
                                from: this.deployer.address,
                                contract: "Mock1InchRouter",
                                args: [],
                                log: true,
                                autoMine: true,
                                ...TRANSACTION_GAS_LIMITS,
                            }
                        );
                        this.mockRouter = await hre.ethers.getContractAt(
                            "Mock1InchRouter",
                            mockRouterAddress
                        );
                    }

                    {
                        const { address: helperAddress } = await deploy(
                            "PulseStrategyV2Helper",
                            {
                                from: this.deployer.address,
                                contract: "PulseStrategyV2Helper",
                                args: [],
                                log: true,
                                autoMine: true,
                                ...TRANSACTION_GAS_LIMITS,
                            }
                        );

                        this.strategyHelper = await ethers.getContractAt(
                            "PulseStrategyV2Helper",
                            helperAddress
                        );
                    }
                    const { address: strategyAddress } = await deploy(
                        "PulseStrategyV2",
                        {
                            from: this.deployer.address,
                            contract: "PulseStrategyV2",
                            args: [uniswapV3PositionManager],
                            log: true,
                            autoMine: true,
                            ...TRANSACTION_GAS_LIMITS,
                        }
                    );

                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let erc20VaultNft = startNft;
                    let uniV3VaultNft = startNft + 1;
                    let erc20RootVaultNft = startNft + 2;

                    const { address: uniV3Helper } =
                        await hre.ethers.getContract("UniV3Helper");

                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                500,
                                uniV3Helper,
                            ],
                            delayedStrategyParams: [2],
                        }
                    );

                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );

                    this.erc20Vault = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    );

                    const uniV3Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        uniV3VaultNft
                    );

                    this.uniV3Vault = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault
                    );

                    const strategy = await hre.ethers.getContractAt(
                        "PulseStrategyV2",
                        strategyAddress
                    );
                    this.subject = strategy as PulseStrategyV2;

                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [erc20VaultNft, uniV3VaultNft],
                        strategy.address,
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

                    await mint(
                        "USDC",
                        this.mockRouter.address,
                        this.deployerUsdcAmount
                    );
                    await mint(
                        "WETH",
                        this.mockRouter.address,
                        this.deployerWethAmount
                    );

                    for (let addr of [
                        this.subject.address,
                        this.erc20RootVault.address,
                        this.swapRouter.address,
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
                    const { address: allowAllValidatorAddress } = await deploy(
                        "AllowAllValidator",
                        {
                            from: this.admin.address,
                            contract: "AllowAllValidator",
                            args: [this.protocolGovernance.address],
                            log: true,
                            autoMine: true,
                            ...TRANSACTION_GAS_LIMITS,
                        }
                    );
                    await this.protocolGovernance
                        .connect(this.admin)
                        .stageValidator(
                            this.mockRouter.address,
                            allowAllValidatorAddress
                        );
                    await this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(this.mockRouter.address, [4]);
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitAllValidatorsSurpassedDelay();
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();

                    await this.subject.connect(this.deployer).initialize(
                        {
                            router: this.mockRouter.address,
                            erc20Vault: this.erc20Vault.address,
                            uniV3Vault: this.uniV3Vault.address,
                            tokens: tokens,
                        },
                        this.deployer.address
                    );

                    await this.subject
                        .connect(this.deployer)
                        .updateMutableParams({
                            priceImpactD6: 0,
                            defaultIntervalWidth: 4200,
                            maxPositionLengthInTicks: 10000,
                            maxDeviationForVaultPool: 50,
                            timespanForAverageTick: 60,
                            neighborhoodFactorD: 10 ** 7 * 15,
                            extensionFactorD: 10 ** 9 * 2,
                            swapSlippageD: 10 ** 7,
                            swappingAmountsCoefficientD: 10 ** 7,
                            minSwapAmounts: [
                                BigNumber.from(10).pow(6),
                                BigNumber.from(10).pow(15),
                            ],
                        });

                    await this.subject
                        .connect(this.deployer)
                        .updateDesiredAmounts({
                            amount0Desired: 10 ** 5,
                            amount1Desired: 10 ** 9,
                        });
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        const push = async (delta: BigNumber, tokenName: string) => {
            const n = 1;
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
            await sleep(this.governanceDelay);
        };

        describe("#rebalance", () => {
            it("test", async () => {
                const pullExistentials =
                    await this.erc20RootVault.pullExistentials();
                await mint(
                    "USDC",
                    this.subject.address,
                    this.deployerUsdcAmount
                );
                await mint(
                    "WETH",
                    this.subject.address,
                    this.deployerWethAmount
                );

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

                // deposit to zero-vault
                await this.erc20RootVault.deposit(
                    [pullExistentials[0].pow(2), pullExistentials[1].pow(2)],
                    0,
                    []
                );

                // normal deposit
                await this.erc20RootVault.deposit(
                    [
                        pullExistentials[0].pow(2).mul(10),
                        pullExistentials[1].pow(2).mul(10),
                    ],
                    0,
                    []
                );

                const getExpectedAmount = async (
                    tokenIn: string,
                    amountIn: BigNumber
                ) => {
                    const sqrtPriceX96 = (await this.pool.slot0()).sqrtPriceX96;
                    let priceX96 = sqrtPriceX96.mul(sqrtPriceX96).div(Q96);
                    if (tokenIn == (await this.pool.token1())) {
                        priceX96 = Q96.mul(Q96).div(priceX96);
                    }
                    return amountIn.mul(priceX96).div(Q96);
                };

                const processSwap = async () => {
                    const swapData =
                        await this.strategyHelper.calculateAmountForSwap(
                            this.subject.address
                        );
                    const expectedAmountOut = await getExpectedAmount(
                        swapData.from,
                        swapData.amountIn
                    );
                    const dataForMockRouter = await this.mockRouter.getData(
                        swapData.from,
                        swapData.to,
                        swapData.amountIn,
                        expectedAmountOut
                    );

                    await this.subject
                        .connect(this.deployer)
                        .rebalance(
                            BigNumber.from(10).pow(10),
                            dataForMockRouter,
                            0
                        );
                    const uniV3Nft = await this.uniV3Vault.uniV3Nft();
                    const { tickLower, tickUpper } =
                        await this.positionManager.positions(uniV3Nft);
                    const spotTick = (await this.pool.slot0()).tick.toString();

                    console.log(
                        tickLower.toString(),
                        tickUpper.toString(),
                        spotTick.toString()
                    );
                };

                await processSwap();
                for (var i = 0; i < 6; i++) {
                    await push(BigNumber.from(10).pow(6).mul(10000000), "USDC");
                    await processSwap();
                }
            });
        });
    }
);
