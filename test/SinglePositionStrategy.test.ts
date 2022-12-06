import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, sleep } from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    YearnVault,
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
import { IUniswapV3Pool } from "./types/IUniswapV3Pool";

import {
    ImmutableParamsStruct,
    MutableParamsStruct,
    RestrictionsStruct,
} from "./types/SinglePositionStrategy";

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
    firstPool: IUniswapV3Pool;
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

                    /*
                     * Configure & deploy subvaults
                     */
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

                    await deploy("UniV3Helper", {
                        from: this.deployer.address,
                        contract: "UniV3Helper",
                        args: [],
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

                    const { uniswapV3PositionManager, uniswapV3Router } =
                        await getNamedAccounts();
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
                        // halfOfShortInterval: 1800,
                        // domainLowerTick: 190800,
                        // domainUpperTick: 219600,
                        // amount0ForMint: 10 ** 5,
                        // amount1ForMint: 10 ** 9,
                        // erc20CapitalRatioD: 5000000,
                        // uniV3Weights: this.weights,
                        // swapPool: this.firstPool.address,
                        // maxTickDeviation: 100,
                        // averageTickTimespan: 60,
                    } as MutableParamsStruct;

                    this.tickSpacing = 600;
                    const params = [
                        {
                            // tokens: tokens,
                            // erc20Vault: this.erc20Vault.address,
                            // moneyVault: this.yearnVault.address,
                            // router: this.swapRouter.address,
                            // rebalancer: rebalancerAddress,
                            // uniV3Vaults: this.uniV3Vaults,
                            // tickSpacing: this.tickSpacing,
                        } as ImmutableParamsStruct,
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

                    const immutableParams =
                        await this.subject.immutableParams();
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

                    /*
                     * Configure oracles for the HStrategy
                     */

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

        describe.only("#rebalance", () => {
            it("works correctly", async () => {});
        });
    }
);
