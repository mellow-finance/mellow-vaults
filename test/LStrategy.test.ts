import { expect } from "chai";
import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";

import { contract } from "./library/setup";
import {
    ERC20Vault,
    LStrategy,
    LStrategyHelper,
    MockCowswap,
    MockOracle,
    UniV3Vault,
} from "./types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { abi as ICurvePool } from "./helpers/curvePoolABI.json";
import { abi as IWETH } from "./helpers/wethABI.json";
import { abi as IWSTETH } from "./helpers/wstethABI.json";
import { mint, randomAddress, sleep, withSigner } from "./library/Helpers";
import { BigNumber } from "ethers";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../deploy/0000_utils";
import Exceptions from "./library/Exceptions";
import { ERC20 } from "./library/Types";
import { randomBytes } from "ethers/lib/utils";
import { TickMath } from "@uniswap/v3-sdk";
import { sqrt } from "@uniswap/sdk-core";
import JSBI from "jsbi";
import { uintToBytes32 } from "../tasks/base";
import { T } from "ramda";

type CustomContext = {
    uniV3LowerVault: UniV3Vault;
    uniV3UpperVault: UniV3Vault;
    erc20Vault: ERC20Vault;
    cowswap: MockCowswap;
    mockOracle: MockOracle;
    orderHelper: LStrategyHelper;
};

type DeployOptions = {};

contract<LStrategy, DeployOptions, CustomContext>("LStrategy", function () {
    const uniV3PoolFee = 500;
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const { uniswapV3PositionManager, uniswapV3Router } =
                    await getNamedAccounts();

                this.swapRouter = await ethers.getContractAt(
                    ISwapRouter,
                    uniswapV3Router
                );

                this.positionManager = await ethers.getContractAt(
                    INonfungiblePositionManager,
                    uniswapV3PositionManager
                );

                this.calculateTvl = async () => {
                    let erc20tvl = (await this.erc20Vault.tvl())[0];
                    let erc20OverallTvl = erc20tvl[0].add(erc20tvl[1]);
                    let lowerVaultTvl = (await this.uniV3LowerVault.tvl())[0];
                    let upperVaultTvl = (await this.uniV3UpperVault.tvl())[0];
                    let uniV3OverallTvl = ethers.constants.Zero;
                    for (let i = 0; i < 2; ++i) {
                        uniV3OverallTvl = uniV3OverallTvl
                            .add(lowerVaultTvl[i])
                            .add(upperVaultTvl[i]);
                    }
                    return [erc20OverallTvl, uniV3OverallTvl];
                };

                this.grantPermissions = async () => {
                    let tokenId = await ethers.provider.send(
                        "eth_getStorageAt",
                        [
                            this.erc20Vault.address,
                            "0x4", // address of _nft
                        ]
                    );
                    await withSigner(
                        this.erc20RootVault.address,
                        async (erc20RootVaultSigner) => {
                            await this.vaultRegistry
                                .connect(erc20RootVaultSigner)
                                .approve(this.subject.address, tokenId);
                        }
                    );

                    await this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(this.wsteth.address, [
                            PermissionIdsLibrary.ERC20_TRANSFER,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitPermissionGrants(this.wsteth.address);

                    await this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(this.cowswap.address, [
                            PermissionIdsLibrary.ERC20_APPROVE,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitPermissionGrants(this.cowswap.address);
                };

                this.swapTokens = async (
                    senderAddress: string,
                    recipientAddress: string,
                    tokenIn: ERC20,
                    tokenOut: ERC20,
                    amountIn: BigNumber
                ) => {
                    await withSigner(senderAddress, async (senderSigner) => {
                        await tokenIn
                            .connect(senderSigner)
                            .approve(
                                this.swapRouter.address,
                                ethers.constants.MaxUint256
                            );
                        let params = {
                            tokenIn: tokenIn.address,
                            tokenOut: tokenOut.address,
                            fee: uniV3PoolFee,
                            recipient: recipientAddress,
                            deadline: ethers.constants.MaxUint256,
                            amountIn: amountIn,
                            amountOutMinimum: 0,
                            sqrtPriceLimitX96: 0,
                        };
                        await this.swapRouter
                            .connect(senderSigner)
                            .exactInputSingle(params);
                    });
                };

                await this.weth.approve(
                    uniswapV3PositionManager,
                    ethers.constants.MaxUint256
                );
                await this.wsteth.approve(
                    uniswapV3PositionManager,
                    ethers.constants.MaxUint256
                );

                this.preparePush = async ({
                    vault,
                    tickLower = -887220,
                    tickUpper = 887220,
                    wethAmount = BigNumber.from(10).pow(18).mul(100),
                    wstethAmount = BigNumber.from(10).pow(18).mul(100),
                }: {
                    vault: any;
                    tickLower?: number;
                    tickUpper?: number;
                    wethAmount?: BigNumber;
                    wstethAmount?: BigNumber;
                }) => {
                    const mintParams = {
                        token0: this.wsteth.address,
                        token1: this.weth.address,
                        fee: 500,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        amount0Desired: wstethAmount,
                        amount1Desired: wethAmount,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: this.deployer.address,
                        deadline: ethers.constants.MaxUint256,
                    };
                    const result = await this.positionManager.callStatic.mint(
                        mintParams
                    );
                    await this.positionManager.mint(mintParams);
                    await this.positionManager.functions[
                        "safeTransferFrom(address,address,uint256)"
                    ](this.deployer.address, vault.address, result.tokenId);
                };

                await this.protocolGovernance
                    .connect(this.admin)
                    .stagePermissionGrants(this.wsteth.address, [
                        PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                    ]);
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitPermissionGrants(this.wsteth.address);

                const tokens = [this.weth.address, this.wsteth.address]
                    .map((t) => t.toLowerCase())
                    .sort();
                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let uniV3LowerVaultNft = startNft;
                let uniV3UpperVaultNft = startNft + 1;
                let erc20VaultNft = startNft + 2;
                let uniV3Helper = (await ethers.getContract("UniV3Helper"))
                    .address;
                await setupVault(
                    hre,
                    uniV3LowerVaultNft,
                    "UniV3VaultGovernance",
                    {
                        createVaultArgs: [
                            tokens,
                            this.deployer.address,
                            uniV3PoolFee,
                            uniV3Helper,
                        ],
                    }
                );
                await setupVault(
                    hre,
                    uniV3UpperVaultNft,
                    "UniV3VaultGovernance",
                    {
                        createVaultArgs: [
                            tokens,
                            this.deployer.address,
                            uniV3PoolFee,
                            uniV3Helper,
                        ],
                    }
                );
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                const { deploy } = deployments;
                let cowswapDeployParams = await deploy("MockCowswap", {
                    from: this.deployer.address,
                    contract: "MockCowswap",
                    args: [],
                    log: true,
                    autoMine: true,
                });
                this.cowswap = await ethers.getContractAt(
                    "MockCowswap",
                    cowswapDeployParams.address
                );

                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );
                const uniV3LowerVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    uniV3LowerVaultNft
                );
                const uniV3UpperVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    uniV3UpperVaultNft
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );

                this.uniV3LowerVault = await ethers.getContractAt(
                    "UniV3Vault",
                    uniV3LowerVault
                );

                this.uniV3UpperVault = await ethers.getContractAt(
                    "UniV3Vault",
                    uniV3UpperVault
                );

                let strategyHelper = await deploy("LStrategyHelper", {
                    from: this.deployer.address,
                    contract: "LStrategyHelper",
                    args: [cowswapDeployParams.address],
                    log: true,
                    autoMine: true,
                });

                let strategyDeployParams = await deploy("LStrategy", {
                    from: this.deployer.address,
                    contract: "LStrategy",
                    args: [
                        uniswapV3PositionManager,
                        cowswapDeployParams.address,
                        this.erc20Vault.address,
                        this.uniV3LowerVault.address,
                        this.uniV3UpperVault.address,
                        strategyHelper.address,
                        this.admin.address,
                    ],
                    log: true,
                    autoMine: true,
                });

                this.orderHelper = await ethers.getContractAt(
                    "LStrategyHelper",
                    strategyHelper.address
                );

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft, uniV3LowerVaultNft, uniV3UpperVaultNft],
                    this.deployer.address,
                    this.deployer.address
                );

                const erc20RootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft + 1
                );

                this.erc20RootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVault
                );

                let wstethValidator = await deploy("ERC20Validator", {
                    from: this.deployer.address,
                    contract: "ERC20Validator",
                    args: [this.protocolGovernance.address],
                    log: true,
                    autoMine: true,
                });

                await this.protocolGovernance
                    .connect(this.admin)
                    .stageValidator(
                        this.wsteth.address,
                        wstethValidator.address
                    );
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitValidator(this.wsteth.address);

                let cowswapValidatorDeployParams = await deploy(
                    "CowswapValidator",
                    {
                        from: this.deployer.address,
                        contract: "CowswapValidator",
                        args: [this.protocolGovernance.address],
                        log: true,
                        autoMine: true,
                    }
                );

                await this.protocolGovernance
                    .connect(this.admin)
                    .stageValidator(
                        this.cowswap.address,
                        cowswapValidatorDeployParams.address
                    );
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitValidator(this.cowswap.address);

                this.subject = await ethers.getContractAt(
                    "LStrategy",
                    strategyDeployParams.address
                );

                const weth = await ethers.getContractAt(
                    IWETH,
                    this.weth.address
                );

                const wsteth = await ethers.getContractAt(
                    IWSTETH,
                    this.wsteth.address
                );

                const curvePool = await ethers.getContractAt(
                    ICurvePool,
                    "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022" // address of curve weth-wsteth
                );
                this.curvePool = curvePool;

                const steth = await ethers.getContractAt(
                    "ERC20Token",
                    "0xae7ab96520de3a18e5e111b5eaab095312d7fe84"
                );

                await mint(
                    "WETH",
                    this.subject.address,
                    BigNumber.from(10).pow(18).mul(4000)
                );
                await mint(
                    "WETH",
                    this.deployer.address,
                    BigNumber.from(10).pow(18).mul(4000)
                );
                await this.weth.approve(
                    curvePool.address,
                    ethers.constants.MaxUint256
                );
                await steth.approve(
                    this.wsteth.address,
                    ethers.constants.MaxUint256
                );
                await weth.withdraw(BigNumber.from(10).pow(18).mul(2000));
                const options = { value: BigNumber.from(10).pow(18).mul(2000) };
                await curvePool.exchange(
                    0,
                    1,
                    BigNumber.from(10).pow(18).mul(2000),
                    ethers.constants.Zero,
                    options
                );
                await wsteth.wrap(BigNumber.from(10).pow(18).mul(1999));

                // for (let address of [
                //     this.uniV3UpperVault.address,
                //     this.uniV3LowerVault.address,
                //     this.erc20Vault.address,
                // ]) {
                //     for (let token of [this.weth, this.wsteth]) {
                //         await token.transfer(
                //             address,
                //             BigNumber.from(10).pow(18).mul(500)
                //         );
                //     }
                // }

                await wsteth.transfer(
                    this.subject.address,
                    BigNumber.from(10).pow(18).mul(3)
                );

                this.curvePoll = await ethers.getContractAt(
                    ICurvePool,
                    "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022" // address of curve weth-wsteth
                );

                this.mintFunds = async (base: BigNumber) => {
                    const steth = await ethers.getContractAt(
                        "ERC20Token",
                        "0xae7ab96520de3a18e5e111b5eaab095312d7fe84"
                    );
                    const weth = await ethers.getContractAt(
                        IWETH,
                        this.weth.address
                    );

                    const wsteth = await ethers.getContractAt(
                        IWSTETH,
                        this.wsteth.address
                    );

                    await mint("WETH", this.subject.address, base.mul(4000));
                    await mint("WETH", this.deployer.address, base.mul(4000));

                    await weth.withdraw(base.mul(2000));
                    const options = { value: base.mul(2000) };
                    await this.curvePool.exchange(
                        0,
                        1,
                        base.mul(2000),
                        ethers.constants.Zero,
                        options
                    );
                    await wsteth.wrap(base.mul(1999));
                    await wsteth.transfer(this.subject.address, base.mul(3));
                };

                this.getUniV3Tick = async () => {
                    let pool = await ethers.getContractAt(
                        "IUniswapV3Pool",
                        await this.uniV3LowerVault.pool()
                    );

                    const currentState = await pool.slot0();
                    return BigNumber.from(currentState.tick);
                };

                this.grantPermissionsUniV3Vaults = async () => {
                    for (let vault of [
                        this.uniV3UpperVault,
                        this.uniV3LowerVault,
                    ]) {
                        let tokenId = await ethers.provider.send(
                            "eth_getStorageAt",
                            [
                                vault.address,
                                "0x4", // address of _nft
                            ]
                        );
                        await withSigner(
                            this.erc20RootVault.address,
                            async (erc20RootVaultSigner) => {
                                await this.vaultRegistry
                                    .connect(erc20RootVaultSigner)
                                    .approve(this.subject.address, tokenId);
                            }
                        );
                    }
                };

                this.updateMockOracle = (currentTick: BigNumber) => {
                    let sqrtPriceX96 = BigNumber.from(
                        TickMath.getSqrtRatioAtTick(
                            currentTick.toNumber()
                        ).toString()
                    );
                    let priceX96 = sqrtPriceX96
                        .mul(sqrtPriceX96)
                        .div(BigNumber.from(2).pow(96));
                    this.mockOracle.updatePrice(priceX96);
                };

                this.swapWethToWsteth = async (number: BigNumber) => {
                    const weth = await ethers.getContractAt(
                        IWETH,
                        this.weth.address
                    );
                    const wsteth = await ethers.getContractAt(
                        IWSTETH,
                        this.wsteth.address
                    );
                    const balance = await wsteth.balanceOf(
                        this.deployer.address
                    );
                    number = number.lt(balance) ? number : balance;
                    await withSigner(
                        this.erc20Vault.address,
                        async (signer) => {
                            await weth
                                .connect(signer)
                                .transfer(this.deployer.address, number);
                        }
                    );
                    await wsteth.transfer(this.erc20Vault.address, number);
                };

                this.swapWstethToWeth = async (number: BigNumber) => {
                    const weth = await ethers.getContractAt(
                        IWETH,
                        this.weth.address
                    );
                    const wsteth = await ethers.getContractAt(
                        IWSTETH,
                        this.wsteth.address
                    );
                    const balance = await weth.balanceOf(this.deployer.address);
                    number = number.lt(balance) ? number : balance;
                    await withSigner(
                        this.erc20Vault.address,
                        async (signer) => {
                            await wsteth
                                .connect(signer)
                                .transfer(this.deployer.address, number);
                        }
                    );
                    await weth.transfer(this.erc20Vault.address, number);
                };

                this.trySwapERC20 = async () => {
                    let erc20Tvl = await this.erc20Vault.tvl();
                    let tokens = [this.wsteth, this.weth];
                    for (let i = 0; i < 2; ++i) {
                        if (erc20Tvl[0][i].eq(BigNumber.from(0))) {
                            if (i == 0) {
                                await this.swapWethToWsteth(
                                    erc20Tvl[0][1 - i].div(2)
                                );
                            } else {
                                await this.swapWstethToWeth(
                                    erc20Tvl[0][1 - i].div(2)
                                );
                            }
                            // let otherTokenAmount = erc20Tvl[0][1 - i];
                            // await this.swapTokens(
                            // this.erc20Vault.address,
                            // this.erc20Vault.address,
                            // tokens[1 - i],
                            // tokens[i],
                            // otherTokenAmount.div(2)
                            // );
                        }
                    }
                };

                this.balanceERC20 = async () => {
                    let erc20Tvl = await this.erc20Vault.tvl();
                    let tokens = [this.wsteth, this.weth];
                    let delta = erc20Tvl[0][0].sub(erc20Tvl[0][1]);

                    if (delta.lt(BigNumber.from(-1))) {
                        await this.swapTokens(
                            this.erc20Vault.address,
                            this.erc20Vault.address,
                            tokens[1],
                            tokens[0],
                            delta.div(2).mul(-1)
                        );
                    }

                    if (delta.gt(BigNumber.from(1))) {
                        await this.swapTokens(
                            this.erc20Vault.address,
                            this.erc20Vault.address,
                            tokens[0],
                            tokens[1],
                            delta.div(2)
                        );
                    }
                };

                this.getExpectedRatio = async () => {
                    const tokens = [this.wsteth.address, this.weth.address];
                    const targetPriceX96 = await this.subject.targetPrice(
                        tokens[0],
                        tokens[1],
                        await this.subject.tradingParams()
                    );
                    const sqrtTargetPriceX96 = BigNumber.from(
                        sqrt(JSBI.BigInt(targetPriceX96)).toString()
                    );
                    const targetTick = TickMath.getTickAtSqrtRatio(
                        JSBI.BigInt(
                            sqrtTargetPriceX96
                                .mul(BigNumber.from(2).pow(48))
                                .toString()
                        )
                    );
                    return await this.subject.targetUniV3LiquidityRatio(
                        targetTick
                    );
                };

                this.calculateRatioDeviationMeasure = async (
                    x: BigNumber,
                    y: BigNumber
                ) => {
                    let delta = x.sub(y).abs();
                    return (await this.subject.DENOMINATOR())
                        .div(delta.add(1))
                        .gt(BigNumber.from(50));
                };

                this.calculateDeviationMeasure = async (
                    x: BigNumber,
                    y: BigNumber
                ) => {
                    let delta = x.sub(y).abs();
                    return x
                        .abs()
                        .add(y.abs())
                        .div(delta.add(1))
                        .gt(BigNumber.from(100));
                };

                let oracleDeployParams = await deploy("MockOracle", {
                    from: this.deployer.address,
                    contract: "MockOracle",
                    args: [],
                    log: true,
                    autoMine: true,
                });

                this.mockOracle = await ethers.getContractAt(
                    "MockOracle",
                    oracleDeployParams.address
                );

                this.getVaultStats = async (vault: UniV3Vault) => {
                    const nft = vault.uniV3Nft();
                    const result = await this.positionManager.positions(nft);
                    return {
                        tickLower: result[5],
                        tickUpper: result[6],
                        liquidity: result[7],
                    };
                };

                this.getVaultsLiquidityRatio = async () => {
                    let lowerVault = await ethers.getContractAt(
                        "UniV3Vault",
                        await this.subject.lowerVault()
                    );
                    let upperVault = await ethers.getContractAt(
                        "UniV3Vault",
                        await this.subject.upperVault()
                    );
                    const [, , , , , , , lowerVaultLiquidity, , , ,] =
                        await this.positionManager.positions(
                            await lowerVault.uniV3Nft()
                        );
                    const [, , , , , , , upperVaultLiquidity, , , ,] =
                        await this.positionManager.positions(
                            await upperVault.uniV3Nft()
                        );
                    const total = lowerVaultLiquidity.add(upperVaultLiquidity);
                    const DENOMINATOR = await this.subject.DENOMINATOR();
                    return DENOMINATOR.sub(
                        lowerVaultLiquidity.mul(DENOMINATOR).div(total)
                    );
                };

                this.submitToERC20Vault = async () => {
                    for (let token of [this.weth, this.wsteth]) {
                        await token.transfer(
                            this.erc20Vault.address,
                            BigNumber.from(10).pow(18).mul(500)
                        );
                    }
                };

                this.calculateCapital = async (
                    vault: UniV3Vault | ERC20Vault
                ) => {
                    await this.updateMockOracle(await this.getUniV3Tick());
                    const targetPriceX96 = await this.subject.targetPrice(
                        this.wsteth.address,
                        this.weth.address,
                        await this.subject.tradingParams()
                    );
                    let [minTvl, maxTvl] = await vault.tvl();
                    return minTvl[0]
                        .add(maxTvl[0])
                        .div(2)
                        .mul(targetPriceX96)
                        .div(BigNumber.from(2).pow(96))
                        .add(minTvl[1].add(maxTvl[1]).div(2));
                };

                await this.uniV3VaultGovernance
                    .connect(this.admin)
                    .stageDelayedProtocolParams({
                        positionManager: uniswapV3PositionManager,
                        oracle: oracleDeployParams.address,
                    });
                await sleep(86400);
                await this.uniV3VaultGovernance
                    .connect(this.admin)
                    .commitDelayedProtocolParams();

                await this.subject.connect(this.admin).updateTradingParams({
                    maxSlippageD: BigNumber.from(10).pow(7),
                    oracleSafetyMask: 0x20,
                    orderDeadline: 86400 * 30,
                    oracle: oracleDeployParams.address,
                    maxFee0: BigNumber.from(10).pow(9),
                    maxFee1: BigNumber.from(10).pow(9),
                });

                await this.subject.connect(this.admin).updateRatioParams({
                    erc20UniV3CapitalRatioD: BigNumber.from(10).pow(7).mul(5), // 0.05 * DENOMINATOR
                    erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5), // 0.5 * DENOMINATOR
                    minErc20UniV3CapitalRatioDeviationD:
                        BigNumber.from(10).pow(8),
                    minErc20TokenRatioDeviationD: BigNumber.from(10)
                        .pow(8)
                        .div(2),
                    minUniV3LiquidityRatioDeviationD: BigNumber.from(10)
                        .pow(8)
                        .div(2),
                });

                await this.subject.connect(this.admin).updateOtherParams({
                    intervalWidthInTicks: 100,
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    rebalanceDeadline: BigNumber.from(10).pow(6),
                });

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#rebalance integration scenarios", () => {
        //open initial positions of equal size and some ticks
        beforeEach(async () => {
            for (let vault of [this.uniV3UpperVault, this.uniV3LowerVault]) {
                for (let token of [this.weth, this.wsteth]) {
                    await withSigner(vault.address, async (signer) => {
                        await token
                            .connect(signer)
                            .approve(
                                this.erc20Vault.address,
                                ethers.constants.MaxUint256
                            );
                    });
                }
            }

            await this.grantPermissions();
            await this.mintFunds(BigNumber.from(10).pow(18));

            this.semiPositionRange = 60;

            const currentTick = await this.getUniV3Tick();
            let tickLeftLower =
                currentTick
                    .div(this.semiPositionRange)
                    .mul(this.semiPositionRange)
                    .toNumber() - this.semiPositionRange;
            let tickLeftUpper = tickLeftLower + 2 * this.semiPositionRange;

            let tickRightLower = tickLeftLower + this.semiPositionRange;
            let tickRightUpper = tickLeftUpper + this.semiPositionRange;

            await this.updateMockOracle(currentTick);

            await this.preparePush({
                vault: this.uniV3LowerVault,
                tickLower: tickLeftLower,
                tickUpper: tickLeftUpper,
            });
            await this.preparePush({
                vault: this.uniV3UpperVault,
                tickLower: tickRightLower,
                tickUpper: tickRightUpper,
            });
            await this.grantPermissionsUniV3Vaults();

            await this.subject.connect(this.admin).updateRatioParams({
                erc20UniV3CapitalRatioD: BigNumber.from(10).pow(7).mul(5), // 0.05 * DENOMINATOR
                erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5), // 0.5 * DENOMINATOR
                minErc20UniV3CapitalRatioDeviationD: BigNumber.from(10).pow(5),
                minErc20TokenRatioDeviationD: BigNumber.from(10).pow(8).div(2),
                minUniV3LiquidityRatioDeviationD: BigNumber.from(10)
                    .pow(7)
                    .div(2),
            });
        });

        describe("ERC20 is initially empty", () => {
            describe("UniV3rebalance when ERC20 is empty and no UniV3ERC20rebalance happens", () => {
                it("not reverts and keeps balances in general case", async () => {
                    let depositAmounts =
                        await this.uniV3UpperVault.liquidityToTokenAmounts(
                            await this.subject.DENOMINATOR()
                        );
                    let withdrawAmounts =
                        await this.uniV3LowerVault.liquidityToTokenAmounts(
                            await this.subject.DENOMINATOR()
                        );

                    let tvlsOld = [
                        await this.uniV3LowerVault.tvl(),
                        await this.uniV3UpperVault.tvl(),
                    ];

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rebalanceUniV3Vaults(
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            )
                    ).not.to.be.reverted;

                    if (
                        withdrawAmounts[0] < depositAmounts[0] ||
                        withdrawAmounts[1] < depositAmounts[1]
                    ) {
                        let tvlsNew = [
                            await this.uniV3LowerVault.tvl(),
                            await this.uniV3UpperVault.tvl(),
                        ];
                        for (let i = 0; i < 2; ++i) {
                            for (let j = 0; j < 2; ++j) {
                                for (let k = 0; k < 2; ++k) {
                                    expect(tvlsOld[i][j][k]).to.be.gt(0);
                                    expect(tvlsOld[i][j][k]).to.be.eq(
                                        tvlsNew[i][j][k]
                                    );
                                }
                            }
                        }
                    }
                });
            });

            describe("cycle rebalanceerc20-swap-rebalanceuniv3 happens a lot of times", () => {
                it("everything goes ok", async () => {
                    const mintParams = {
                        token0: this.wsteth.address,
                        token1: this.weth.address,
                        fee: 500,
                        tickLower: -2000,
                        tickUpper: 2000,
                        amount0Desired: BigNumber.from(10).pow(20).mul(5),
                        amount1Desired: BigNumber.from(10).pow(20).mul(5),
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: this.deployer.address,
                        deadline: ethers.constants.MaxUint256,
                    };
                    //mint a position in pull to provide liquidity for future swaps
                    await this.positionManager.mint(mintParams);
                    for (let i = 0; i < 30; ++i) {
                        //balance tokens in ERC20
                        await this.balanceERC20();

                        await expect(
                            this.subject
                                .connect(this.admin)
                                .rebalanceERC20UniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).not.to.be.reverted;

                        await this.trySwapERC20();

                        // changes price
                        await this.swapTokens(
                            this.deployer.address,
                            this.deployer.address,
                            this.weth,
                            this.wsteth,
                            BigNumber.from(10).pow(17).mul(30)
                        );

                        const currentTick = await this.getUniV3Tick();
                        await this.updateMockOracle(currentTick);

                        await expect(
                            this.subject
                                .connect(this.admin)
                                .rebalanceUniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).not.to.be.reverted;
                    }
                });
            });

            describe("batches of rebalances after small price changes", () => {
                it("rebalance converges to target ratio", async () => {
                    let tokenFirst = this.weth;
                    let tokenSecond = this.wsteth;
                    for (let iter = 0; iter < 4; ++iter) {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .rebalanceERC20UniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).not.to.be.reverted;
                        await this.swapTokens(
                            this.deployer.address,
                            this.deployer.address,
                            tokenFirst,
                            tokenSecond,
                            BigNumber.from(10).pow(18).mul(5)
                        );

                        for (let rebalance = 0; rebalance < 10; ++rebalance) {
                            await this.trySwapERC20();

                            const currentTick = await this.getUniV3Tick();
                            await this.updateMockOracle(currentTick);

                            // await expect(
                            await this.subject
                                .connect(this.admin)
                                .rebalanceUniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                );
                            // ).not.to.be.reverted;
                            // if (newLiquidityRatio.eq(prevLiquidityRatio)) {
                            // break;
                            // }
                        }
                        const [neededRatio, flag] =
                            await this.getExpectedRatio();
                        const liquidityRatio =
                            await this.getVaultsLiquidityRatio();
                        expect(
                            await this.calculateRatioDeviationMeasure(
                                neededRatio,
                                liquidityRatio
                            )
                        ).true;
                        [tokenFirst, tokenSecond] = [tokenSecond, tokenFirst];
                    }
                });
            });
        });

        describe("ERC20 has inititally a lot of liquidity", () => {
            beforeEach(async () => {
                await this.submitToERC20Vault();
                let liquidityERC20Vault = await this.erc20Vault.tvl();
                for (let i = 0; i < 2; ++i) {
                    expect(liquidityERC20Vault[0][i]).to.be.gt(0);
                }
            });
            describe("liquidity calculation", () => {
                beforeEach(async () => {
                    this.baseParams = {
                        erc20UniV3CapitalRatioD: BigNumber.from(10).pow(8),
                        erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5),
                        minErc20UniV3CapitalRatioDeviationD:
                            BigNumber.from(10).pow(7),
                        minErc20TokenRatioDeviationD: BigNumber.from(10).pow(7),
                        minUniV3LiquidityRatioDeviationD:
                            BigNumber.from(10).pow(7),
                    };
                    await this.subject
                        .connect(this.admin)
                        .updateRatioParams(this.baseParams);
                    for (let i = 0; i < 10; ++i) {
                        await this.subject
                            .connect(this.admin)
                            .rebalanceUniV3Vaults(
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            );
                        await this.subject
                            .connect(this.admin)
                            .rebalanceERC20UniV3Vaults(
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            );
                        await this.trySwapERC20();
                    }
                });
                describe("erc20 rebalance", () => {
                    describe("when pulling from erc 20 to uni v3", () => {
                        it("works", async () => {
                            let ratioParams = {
                                erc20UniV3CapitalRatioD:
                                    this.baseParams.erc20UniV3CapitalRatioD.div(
                                        2
                                    ),
                                erc20TokenRatioD:
                                    this.baseParams.erc20TokenRatioD,
                                minErc20UniV3CapitalRatioDeviationD:
                                    this.baseParams
                                        .minErc20UniV3CapitalRatioDeviationD,
                                minErc20TokenRatioDeviationD:
                                    this.baseParams
                                        .minErc20TokenRatioDeviationD,
                                minUniV3LiquidityRatioDeviationD:
                                    this.baseParams
                                        .minUniV3LiquidityRatioDeviationD,
                            };
                            await this.subject
                                .connect(this.admin)
                                .updateRatioParams(ratioParams);
                            const {
                                totalPulledAmounts,
                                isNegativeCapitalDelta,
                                percentageIncreaseD,
                            } = await this.subject
                                .connect(this.admin)
                                .callStatic.rebalanceERC20UniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                );
                            const DENOMINATOR =
                                await this.subject.DENOMINATOR();
                            expect(isNegativeCapitalDelta).to.be.false;
                            const lowerVault = await ethers.getContractAt(
                                "UniV3Vault",
                                await this.subject.lowerVault()
                            );
                            const upperVault = await ethers.getContractAt(
                                "UniV3Vault",
                                await this.subject.upperVault()
                            );
                            const lowerVaultStats = await this.getVaultStats(
                                lowerVault
                            );
                            const upperVaultStats = await this.getVaultStats(
                                upperVault
                            );
                            const lowerVaultDelta = percentageIncreaseD
                                .mul(lowerVaultStats.liquidity)
                                .div(DENOMINATOR);
                            const upperVaultDelta = percentageIncreaseD
                                .mul(upperVaultStats.liquidity)
                                .div(DENOMINATOR);
                            let lowerTokenAmounts =
                                await lowerVault.liquidityToTokenAmounts(
                                    lowerVaultDelta
                                );
                            let upperTokenAmounts =
                                await upperVault.liquidityToTokenAmounts(
                                    upperVaultDelta
                                );
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .callStatic.rebalanceERC20UniV3Vaults(
                                        [
                                            lowerTokenAmounts[0].sub(10),
                                            lowerTokenAmounts[1].sub(10),
                                        ],
                                        [
                                            upperTokenAmounts[0].sub(10),
                                            upperTokenAmounts[1].sub(10),
                                        ],
                                        ethers.constants.MaxUint256
                                    )
                            ).not.to.be.reverted;
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .callStatic.rebalanceERC20UniV3Vaults(
                                        [
                                            lowerTokenAmounts[0].add(1),
                                            lowerTokenAmounts[1].add(1),
                                        ],
                                        upperTokenAmounts,
                                        ethers.constants.MaxUint256
                                    )
                            ).to.be.reverted;
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .callStatic.rebalanceERC20UniV3Vaults(
                                        lowerTokenAmounts,
                                        [
                                            upperTokenAmounts[0].add(1),
                                            upperTokenAmounts[1].add(1),
                                        ],
                                        ethers.constants.MaxUint256
                                    )
                            ).to.be.reverted;
                        });
                    });
                    describe("when pulling from uni v3 to erc20", () => {
                        it("works", async () => {
                            let ratioParams = {
                                erc20UniV3CapitalRatioD:
                                    this.baseParams.erc20UniV3CapitalRatioD.mul(
                                        2
                                    ),
                                erc20TokenRatioD:
                                    this.baseParams.erc20TokenRatioD,
                                minErc20UniV3CapitalRatioDeviationD:
                                    this.baseParams
                                        .minErc20UniV3CapitalRatioDeviationD,
                                minErc20TokenRatioDeviationD:
                                    this.baseParams
                                        .minErc20TokenRatioDeviationD,
                                minUniV3LiquidityRatioDeviationD:
                                    this.baseParams
                                        .minUniV3LiquidityRatioDeviationD,
                            };
                            await this.subject
                                .connect(this.admin)
                                .updateRatioParams(ratioParams);
                            const {
                                totalPulledAmounts,
                                isNegativeCapitalDelta,
                                percentageIncreaseD,
                            } = await this.subject
                                .connect(this.admin)
                                .callStatic.rebalanceERC20UniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                );
                            const DENOMINATOR =
                                await this.subject.DENOMINATOR();
                            expect(isNegativeCapitalDelta).to.be.true;
                            const lowerVault = await ethers.getContractAt(
                                "UniV3Vault",
                                await this.subject.lowerVault()
                            );
                            const upperVault = await ethers.getContractAt(
                                "UniV3Vault",
                                await this.subject.upperVault()
                            );
                            const lowerVaultStats = await this.getVaultStats(
                                lowerVault
                            );
                            const upperVaultStats = await this.getVaultStats(
                                upperVault
                            );
                            const lowerVaultDelta = percentageIncreaseD
                                .mul(lowerVaultStats.liquidity)
                                .div(DENOMINATOR);
                            const upperVaultDelta = percentageIncreaseD
                                .mul(upperVaultStats.liquidity)
                                .div(DENOMINATOR);
                            let lowerTokenAmounts =
                                await lowerVault.liquidityToTokenAmounts(
                                    lowerVaultDelta
                                );
                            let upperTokenAmounts =
                                await upperVault.liquidityToTokenAmounts(
                                    upperVaultDelta
                                );
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .callStatic.rebalanceERC20UniV3Vaults(
                                        [
                                            lowerTokenAmounts[0].sub(10),
                                            lowerTokenAmounts[1].sub(10),
                                        ],
                                        [
                                            upperTokenAmounts[0].sub(10),
                                            upperTokenAmounts[1].sub(10),
                                        ],
                                        ethers.constants.MaxUint256
                                    )
                            ).not.to.be.reverted;
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .callStatic.rebalanceERC20UniV3Vaults(
                                        [
                                            lowerTokenAmounts[0].add(1),
                                            lowerTokenAmounts[1].add(1),
                                        ],
                                        upperTokenAmounts,
                                        ethers.constants.MaxUint256
                                    )
                            ).to.be.reverted;
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .callStatic.rebalanceERC20UniV3Vaults(
                                        lowerTokenAmounts,
                                        [
                                            upperTokenAmounts[0].add(1),
                                            upperTokenAmounts[1].add(1),
                                        ],
                                        ethers.constants.MaxUint256
                                    )
                            ).to.be.reverted;
                        });
                    });
                });
                describe("univ3 rebalance", () => {
                    it("works", async () => {
                        await this.swapTokens(
                            this.deployer.address,
                            this.deployer.address,
                            this.weth,
                            this.wsteth,
                            BigNumber.from(10).pow(18).mul(10)
                        );
                        const currentTick = await this.getUniV3Tick();
                        await this.updateMockOracle(currentTick);
                        const {
                            pulledAmounts,
                            pushedAmounts,
                            depositLiquidity,
                            withdrawLiquidity,
                            lowerToUpper,
                        } = await this.subject
                            .connect(this.admin)
                            .callStatic.rebalanceUniV3Vaults(
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            );
                        let fromVault = await ethers.getContractAt(
                            "UniV3Vault",
                            await this.subject.lowerVault()
                        );
                        let toVault = await ethers.getContractAt(
                            "UniV3Vault",
                            await this.subject.upperVault()
                        );
                        expect(
                            withdrawLiquidity.lt(BigNumber.from(2).pow(100))
                        );
                        if (!lowerToUpper) {
                            [toVault, fromVault] = [fromVault, toVault];
                        }
                        const withdrawTokens =
                            await fromVault.liquidityToTokenAmounts(
                                withdrawLiquidity
                            );
                        const depositTokens =
                            await toVault.liquidityToTokenAmounts(
                                depositLiquidity
                            );
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .callStatic.rebalanceUniV3Vaults(
                                    [
                                        withdrawTokens[0].sub(10),
                                        withdrawTokens[1].sub(10),
                                    ],
                                    [
                                        depositTokens[0].sub(10),
                                        depositTokens[1].sub(10),
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).not.to.be.reverted;
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .callStatic.rebalanceUniV3Vaults(
                                    [
                                        withdrawTokens[0].add(1),
                                        withdrawTokens[1].add(1),
                                    ],
                                    [depositTokens[0], depositTokens[1]],
                                    ethers.constants.MaxUint256
                                )
                        ).to.be.reverted;
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .callStatic.rebalanceUniV3Vaults(
                                    [withdrawTokens[0], withdrawTokens[1]],
                                    [
                                        depositTokens[0].add(1),
                                        depositTokens[1].add(1),
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).to.be.reverted;
                    });
                });
            });

            describe("ERC20UniV3Rebalance with empty UniV3", () => {
                it("works correctly", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .manualPull(
                                this.uniV3UpperVault.address,
                                this.erc20Vault.address,
                                [
                                    BigNumber.from(10).pow(30),
                                    BigNumber.from(10).pow(30),
                                ],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            )
                    ).not.to.be.reverted;

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .manualPull(
                                this.uniV3LowerVault.address,
                                this.erc20Vault.address,
                                [
                                    BigNumber.from(10).pow(30),
                                    BigNumber.from(10).pow(30),
                                ],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            )
                    ).not.to.be.reverted;

                    const [, , , , , , , lowerVaultLiquidity, , , ,] =
                        await this.positionManager.positions(
                            await this.uniV3LowerVault.uniV3Nft()
                        );
                    const [, , , , , , , upperVaultLiquidity, , , ,] =
                        await this.positionManager.positions(
                            await this.uniV3UpperVault.uniV3Nft()
                        );

                    expect(lowerVaultLiquidity).to.be.eq(0);
                    expect(upperVaultLiquidity).to.be.eq(0);

                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rebalanceERC20UniV3Vaults(
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            )
                    ).not.to.be.reverted;

                    let erc20Capital = await this.calculateCapital(
                        this.erc20Vault
                    );
                    let uniLowerCapital = await this.calculateCapital(
                        this.uniV3LowerVault
                    );
                    let uniUpperCapital = await this.calculateCapital(
                        this.uniV3UpperVault
                    );
                    expect(
                        await this.calculateDeviationMeasure(
                            erc20Capital.mul(19),
                            uniLowerCapital.add(uniUpperCapital)
                        )
                    ).to.be.true;
                });
            });
            describe("rebalance сall", () => {
                it("converges to desired target ratio", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rebalanceUniV3Vaults(
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            )
                    ).not.to.be.reverted;

                    const [neededRatio, flag] = await this.getExpectedRatio();
                    const liquidityRatio = await this.getVaultsLiquidityRatio();

                    expect(
                        await this.calculateRatioDeviationMeasure(
                            neededRatio,
                            liquidityRatio
                        )
                    ).true;
                });
            });
            describe("multiple rebalance сalls", () => {
                it("stay the same after the first call", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rebalanceUniV3Vaults(
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            )
                    ).not.to.be.reverted;
                    let liquidityBefore = await this.calculateTvl();

                    for (let i = 0; i < 10; ++i) {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .rebalanceUniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).not.to.be.reverted;
                    }
                    let liquidityAfter = await this.calculateTvl();
                    for (let i = 0; i < 2; ++i) {
                        expect(liquidityBefore[i]).to.be.eq(liquidityAfter[i]);
                    }
                });
            });
            describe("batches of rebalances after huge price changes", () => {
                it("rebalance converges to target ratio", async () => {
                    await this.submitToERC20Vault();
                    const initialTick = await this.getUniV3Tick();

                    const mintParams = {
                        token0: this.wsteth.address,
                        token1: this.weth.address,
                        fee: 500,
                        tickLower: -20 * this.semiPositionRange,
                        tickUpper: 20 * this.semiPositionRange,
                        amount0Desired: BigNumber.from(10).pow(20).mul(5),
                        amount1Desired: BigNumber.from(10).pow(20).mul(5),
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: this.deployer.address,
                        deadline: ethers.constants.MaxUint256,
                    };
                    //mint a position in pull to provide liquidity for future swaps
                    await this.positionManager.mint(mintParams);

                    //change price up to some level
                    while (true) {
                        await this.swapTokens(
                            this.deployer.address,
                            this.deployer.address,
                            this.wsteth,
                            this.weth,
                            BigNumber.from(10).pow(18).mul(5)
                        );

                        const currentTick = await this.getUniV3Tick();
                        const delta = currentTick.sub(initialTick).abs();
                        if (
                            delta.gt(
                                BigNumber.from(5).mul(this.semiPositionRange)
                            )
                        ) {
                            break;
                        }
                    }

                    for (let iter = 0; iter < 20; ++iter) {
                        const currentTick = await this.getUniV3Tick();
                        await this.updateMockOracle(currentTick);

                        await expect(
                            this.subject
                                .connect(this.admin)
                                .rebalanceUniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).not.to.be.reverted;

                        const [neededRatio, flag] =
                            await this.getExpectedRatio();
                        const liquidityRatio =
                            await this.getVaultsLiquidityRatio();
                    }

                    const [neededRatio, flag] = await this.getExpectedRatio();
                    const liquidityRatio = await this.getVaultsLiquidityRatio();
                    expect(
                        await this.calculateRatioDeviationMeasure(
                            neededRatio,
                            liquidityRatio
                        )
                    ).true;
                });
            });
        });
    });

    describe("unit tests", () => {
        beforeEach(async () => {
            for (let address of [
                this.uniV3UpperVault.address,
                this.uniV3LowerVault.address,
                this.erc20Vault.address,
            ]) {
                for (let token of [this.weth, this.wsteth]) {
                    await token.transfer(
                        address,
                        BigNumber.from(10).pow(18).mul(500)
                    );
                }
            }
        });

        describe("#updateTradingParams", () => {
            beforeEach(async () => {
                this.baseParams = {
                    maxSlippageD: BigNumber.from(10).pow(6),
                    orderDeadline: 86400 * 30,
                    oracleSafetyMask: 0x20,
                    oracle: this.mellowOracle.address,
                    maxFee0: BigNumber.from(10).pow(9),
                    maxFee1: BigNumber.from(10).pow(9),
                };
            });

            it("updates trading params", async () => {
                await this.subject
                    .connect(this.admin)
                    .updateTradingParams(this.baseParams);
                const expectedParams = [
                    10 ** 6,
                    86400 * 30,
                    BigNumber.from(32),
                    this.mellowOracle.address,
                    BigNumber.from(10).pow(9),
                    BigNumber.from(10).pow(9),
                ];
                let params = await this.subject.tradingParams();
                expect(params.maxSlippageD).to.be.eq(BigNumber.from(10).pow(6));
                expect(params.orderDeadline).to.be.eq(86400 * 30);
                expect(params.oracleSafetyMask).to.be.eq(BigNumber.from(32));
                expect(params.oracle).to.be.eq(this.mellowOracle.address);
                expect(params.maxFee0).to.be.eq(BigNumber.from(10).pow(9));
                expect(params.maxFee1).to.be.eq(BigNumber.from(10).pow(9));
            });
            it("emits TradingParamsUpdated event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .updateTradingParams(this.baseParams)
                ).to.emit(this.subject, "TradingParamsUpdated");
            });

            describe("edge cases:", () => {
                describe("when maxSlippageD is more than DENOMINATOR", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.maxSlippageD = BigNumber.from(10).pow(9).mul(2);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateTradingParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when orderDeadline is more than 30 days", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.orderDeadline = 86400 * 31;
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateTradingParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when oracle has zero address", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        let params = this.baseParams;
                        params.oracle = ethers.constants.AddressZero;
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateTradingParams(params)
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .updateTradingParams(this.baseParams)
                    ).to.not.be.reverted;
                });
                it("not allowed: deployer", async () => {
                    await expect(
                        this.subject.updateTradingParams(this.baseParams)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .updateTradingParams(this.baseParams)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#updateRatioParams", () => {
            beforeEach(async () => {
                this.baseParams = {
                    erc20UniV3CapitalRatioD: BigNumber.from(10).pow(7).mul(5),
                    erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5),
                    minErc20UniV3CapitalRatioDeviationD:
                        BigNumber.from(10).pow(7),
                    minErc20TokenRatioDeviationD: BigNumber.from(10).pow(7),
                    minUniV3LiquidityRatioDeviationD: BigNumber.from(10).pow(7),
                };
            });

            it("updates ratio params", async () => {
                await this.subject
                    .connect(this.admin)
                    .updateRatioParams(this.baseParams);
                const expectedParams = [
                    5 * 10 ** 7,
                    5 * 10 ** 8,
                    10 ** 7,
                    10 ** 7,
                    10 ** 7,
                ];
                expect(await this.subject.ratioParams()).to.be.eqls(
                    expectedParams
                );
            });
            it("emits RatioParamsUpdated event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .updateRatioParams(this.baseParams)
                ).to.emit(this.subject, "RatioParamsUpdated");
            });

            describe("edge cases:", () => {
                describe("when erc20UniV3CapitalRatioD is more than DENOMINATOR", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.erc20UniV3CapitalRatioD = BigNumber.from(10)
                            .pow(9)
                            .mul(2);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateRatioParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when erc20TokenRatioD is more than DENOMINATOR", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.erc20TokenRatioD = BigNumber.from(10)
                            .pow(9)
                            .mul(2);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateRatioParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when minErc20UniV3CapitalRatioDeviationD is more than DENOMINATOR", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.minErc20UniV3CapitalRatioDeviationD =
                            BigNumber.from(10).pow(9).mul(2);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateRatioParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when minErc20TokenRatioDeviationD is more than DENOMINATOR", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.minErc20TokenRatioDeviationD = BigNumber.from(10)
                            .pow(9)
                            .mul(2);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateRatioParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when minUniV3LiquidityRatioDeviationD is more than DENOMINATOR", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.minUniV3LiquidityRatioDeviationD =
                            BigNumber.from(10).pow(9).mul(2);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateRatioParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .updateRatioParams(this.baseParams)
                    ).to.not.be.reverted;
                });
                it("not allowed: deployer", async () => {
                    await expect(
                        this.subject.updateRatioParams(this.baseParams)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .updateRatioParams(this.baseParams)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#updateOtherParams", () => {
            beforeEach(async () => {
                this.baseParams = {
                    intervalWidthInTicks: 100,
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    rebalanceDeadline: BigNumber.from(86400 * 30),
                };
            });

            it("updates other params", async () => {
                await this.subject
                    .connect(this.admin)
                    .updateOtherParams(this.baseParams);
                const returnedParams = await this.subject.otherParams();
                expect(returnedParams.intervalWidthInTicks).eq(100);
                expect(returnedParams.minToken0ForOpening).eq(
                    BigNumber.from(10).pow(6)
                );
                expect(returnedParams.minToken1ForOpening).eq(
                    BigNumber.from(10).pow(6)
                );
                expect(returnedParams.rebalanceDeadline).eq(
                    BigNumber.from(86400 * 30)
                );
            });
            it("emits OtherParamsUpdated event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .updateOtherParams(this.baseParams)
                ).to.emit(this.subject, "OtherParamsUpdated");
            });

            describe("edge cases:", () => {
                describe("when minToken0ForOpening equals zero", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.minToken0ForOpening = BigNumber.from(0);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateOtherParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when minToken0ForOpening is more than 10^9", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.minToken0ForOpening = BigNumber.from(10)
                            .pow(9)
                            .mul(2);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateOtherParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when minToken1ForOpening equals zero", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.minToken1ForOpening = BigNumber.from(0);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateOtherParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when minToken1ForOpening is more than 10^9", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.minToken1ForOpening = BigNumber.from(10)
                            .pow(9)
                            .mul(2);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateOtherParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when rebalanceDeadline is incorrect", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        let params = this.baseParams;
                        params.rebalanceDeadline = BigNumber.from(86400 * 31);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .updateOtherParams(params)
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .updateOtherParams(this.baseParams)
                    ).to.not.be.reverted;
                });
                it("not allowed: deployer", async () => {
                    await expect(
                        this.subject.updateOtherParams(this.baseParams)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .updateOtherParams(this.baseParams)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#targetPrice", () => {
            it("returns target price for specific trading params", async () => {
                let params = {
                    maxSlippageD: BigNumber.from(10).pow(6),
                    orderDeadline: 86400 * 30,
                    oracleSafetyMask: 0x02,
                    oracle: this.mockOracle.address,
                    maxFee0: BigNumber.from(10).pow(9),
                    maxFee1: BigNumber.from(10).pow(9),
                };
                expect(
                    (
                        await this.subject.targetPrice(
                            this.wsteth.address,
                            this.weth.address,
                            params
                        )
                    ).shr(96)
                ).to.be.gt(0);
            });

            describe("edge cases:", () => {
                describe("when address is not an oracle", async () => {
                    it("reverts", async () => {
                        let params = {
                            maxSlippageD: BigNumber.from(10).pow(6),
                            orderDeadline: 86400 * 30,
                            oracleSafetyMask: 0x02,
                            oracle: ethers.constants.AddressZero,
                            maxFee0: BigNumber.from(10).pow(9),
                            maxFee1: BigNumber.from(10).pow(9),
                        };
                        await expect(
                            this.subject.targetPrice(
                                this.wsteth.address,
                                this.weth.address,
                                params
                            )
                        ).to.be.reverted;
                    });
                });
            });
        });

        describe("#targetUniV3LiquidityRatio", () => {
            describe("returns target liquidity ratio", () => {
                describe("when target tick is more, than mid tick", () => {
                    it("returns isNegative false", async () => {
                        await this.preparePush({ vault: this.uniV3LowerVault });
                        const result =
                            await this.subject.targetUniV3LiquidityRatio(1);
                        expect(result.isNegative).to.be.false;
                        expect(result.liquidityRatioD).to.be.equal(
                            BigNumber.from(10).pow(9).div(887220)
                        );
                    });
                });
                describe("when target tick is less, than mid tick", () => {
                    it("returns isNegative true", async () => {
                        await this.preparePush({ vault: this.uniV3LowerVault });
                        const result =
                            await this.subject.targetUniV3LiquidityRatio(-1);
                        expect(result.isNegative).to.be.true;
                        expect(result.liquidityRatioD).to.be.equal(
                            BigNumber.from(10).pow(9).div(887220)
                        );
                    });
                });
            });

            describe("edge cases:", () => {
                describe("when there is no minted position", () => {
                    it("reverts", async () => {
                        await expect(
                            this.subject.targetUniV3LiquidityRatio(0)
                        ).to.be.revertedWith("Invalid token ID");
                    });
                });
            });
        });

        describe("#resetCowswapAllowance", () => {
            it("resets allowance from erc20Vault to cowswap", async () => {
                await withSigner(this.erc20Vault.address, async (signer) => {
                    await this.wsteth
                        .connect(signer)
                        .approve(
                            this.cowswap.address,
                            BigNumber.from(10).pow(18)
                        );
                });
                await this.grantPermissions();
                await this.subject
                    .connect(this.admin)
                    .grantRole(
                        await this.subject.ADMIN_DELEGATE_ROLE(),
                        this.deployer.address
                    );
                await this.subject.resetCowswapAllowance(0);
                expect(
                    await this.wsteth.allowance(
                        this.erc20Vault.address,
                        this.cowswap.address
                    )
                ).to.be.equal(0);
            });
            it("emits CowswapAllowanceReset event", async () => {
                await this.grantPermissions();
                await this.subject
                    .connect(this.admin)
                    .grantRole(
                        await this.subject.ADMIN_DELEGATE_ROLE(),
                        this.deployer.address
                    );
                await expect(this.subject.resetCowswapAllowance(0)).to.emit(
                    this.subject,
                    "CowswapAllowanceReset"
                );
            });

            describe("edge cases:", () => {
                describe("when permissions are not set", () => {
                    it("reverts", async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .resetCowswapAllowance(0)
                        ).to.be.reverted;
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await this.grantPermissions();
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .resetCowswapAllowance(0)
                    ).to.not.be.reverted;
                });
                it("allowed: operator", async () => {
                    await this.grantPermissions();
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .grantRole(
                                await this.subject.ADMIN_DELEGATE_ROLE(),
                                signer.address
                            );
                        await expect(
                            this.subject
                                .connect(signer)
                                .resetCowswapAllowance(0)
                        ).to.not.be.reverted;
                    });
                });
                it("not allowed: any address", async () => {
                    await this.grantPermissions();
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .resetCowswapAllowance(0)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#collectUniFees", () => {
            it("collect fees from both univ3 vaults", async () => {
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await this.uniV3UpperVault.push(
                    [this.wsteth.address, this.weth.address],
                    [
                        BigNumber.from(10).pow(18).mul(1),
                        BigNumber.from(10).pow(18).mul(1),
                    ],
                    []
                );
                await this.uniV3LowerVault.push(
                    [this.wsteth.address, this.weth.address],
                    [
                        BigNumber.from(10).pow(18).mul(1),
                        BigNumber.from(10).pow(18).mul(1),
                    ],
                    []
                );
                await this.swapTokens(
                    this.deployer.address,
                    this.deployer.address,
                    this.wsteth,
                    this.weth,
                    BigNumber.from(10).pow(17).mul(5)
                );

                let lowerVaultFees =
                    await this.uniV3LowerVault.callStatic.collectEarnings();
                let upperVaultFees =
                    await this.uniV3UpperVault.callStatic.collectEarnings();
                let sumFees = await this.subject
                    .connect(this.admin)
                    .callStatic.collectUniFees();
                for (let i = 0; i < 2; ++i) {
                    expect(sumFees[i]).to.be.eq(
                        lowerVaultFees[i].add(upperVaultFees[i])
                    );
                }
                await expect(this.subject.connect(this.admin).collectUniFees())
                    .to.not.be.reverted;
            });
            it("emits FeesCollected event", async () => {
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await expect(
                    this.subject.connect(this.admin).collectUniFees()
                ).to.emit(this.subject, "FeesCollected");
            });

            describe("edge cases:", () => {
                describe("when there is no minted position", () => {
                    it("reverts", async () => {
                        await expect(
                            this.subject.connect(this.admin).collectUniFees()
                        ).to.be.reverted;
                    });
                });
                describe("when there were no swaps", () => {
                    it("returns zeroes", async () => {
                        await this.preparePush({ vault: this.uniV3LowerVault });
                        await this.preparePush({ vault: this.uniV3UpperVault });
                        await this.uniV3UpperVault.push(
                            [this.wsteth.address, this.weth.address],
                            [
                                BigNumber.from(10).pow(18).mul(1),
                                BigNumber.from(10).pow(18).mul(1),
                            ],
                            []
                        );
                        await this.uniV3LowerVault.push(
                            [this.wsteth.address, this.weth.address],
                            [
                                BigNumber.from(10).pow(18).mul(1),
                                BigNumber.from(10).pow(18).mul(1),
                            ],
                            []
                        );

                        let lowerVaultFees =
                            await this.uniV3LowerVault.callStatic.collectEarnings();
                        let upperVaultFees =
                            await this.uniV3UpperVault.callStatic.collectEarnings();
                        for (let i = 0; i < 2; ++i) {
                            lowerVaultFees[i].add(upperVaultFees[i]);
                        }
                        let sumFees = await this.subject
                            .connect(this.admin)
                            .callStatic.collectUniFees();
                        expect(sumFees[0]).to.be.eq(ethers.constants.Zero);
                        expect(sumFees[1]).to.be.eq(ethers.constants.Zero);
                        await expect(
                            this.subject.connect(this.admin).collectUniFees()
                        ).to.not.be.reverted;
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    await this.preparePush({ vault: this.uniV3UpperVault });
                    await expect(
                        this.subject.connect(this.admin).collectUniFees()
                    ).to.not.be.reverted;
                });
                it("allowed: operator", async () => {
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    await this.preparePush({ vault: this.uniV3UpperVault });
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .grantRole(
                                await this.subject.ADMIN_DELEGATE_ROLE(),
                                signer.address
                            );
                        await expect(
                            this.subject.connect(signer).collectUniFees()
                        ).to.not.be.reverted;
                    });
                });
                it("not allowed: any address", async () => {
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    await this.preparePush({ vault: this.uniV3UpperVault });
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).collectUniFees()
                        ).to.be.reverted;
                    });
                });
            });
        });

        describe("#manualPull", () => {
            beforeEach(async () => {
                await withSigner(this.erc20Vault.address, async (signer) => {
                    await this.wsteth
                        .connect(signer)
                        .approve(
                            this.uniV3UpperVault.address,
                            ethers.constants.MaxUint256
                        );
                });

                await withSigner(this.erc20Vault.address, async (signer) => {
                    await this.weth
                        .connect(signer)
                        .approve(
                            this.uniV3UpperVault.address,
                            ethers.constants.MaxUint256
                        );
                });
            });

            it("pull from erc20 to univ3 in non-initialized case returns liquidity to erc20", async () => {
                await this.grantPermissions();

                let prevBalances = [
                    [
                        await this.wsteth.balanceOf(this.erc20Vault.address),
                        await this.weth.balanceOf(this.erc20Vault.address),
                    ],
                    [
                        await this.wsteth.balanceOf(
                            this.uniV3UpperVault.address
                        ),
                        await this.weth.balanceOf(this.uniV3UpperVault.address),
                    ],
                ];

                for (let i = 0; i < 2; ++i) {
                    for (let j = 0; j < 2; ++j) {
                        expect(prevBalances[i][j]).to.be.eq(
                            BigNumber.from(10).pow(18).mul(500)
                        );
                    }
                }

                await this.subject
                    .connect(this.admin)
                    .manualPull(
                        this.erc20Vault.address,
                        this.uniV3UpperVault.address,
                        [
                            BigNumber.from(10).pow(18).mul(100),
                            BigNumber.from(10).pow(18).mul(100),
                        ],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    );
                let endBalances = [
                    [
                        await this.wsteth.balanceOf(this.erc20Vault.address),
                        await this.weth.balanceOf(this.erc20Vault.address),
                    ],
                    [
                        await this.wsteth.balanceOf(
                            this.uniV3UpperVault.address
                        ),
                        await this.weth.balanceOf(this.uniV3UpperVault.address),
                    ],
                ];

                for (let j = 0; j < 2; ++j) {
                    expect(endBalances[0][j]).to.be.eq(
                        BigNumber.from(10).pow(18).mul(1000)
                    );
                }
                for (let j = 0; j < 2; ++j) {
                    expect(endBalances[1][j]).to.be.eq(BigNumber.from(0));
                }
            });

            it("makes pull", async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3UpperVault });

                //mock pull to pull all non-requested liquidity
                await this.subject
                    .connect(this.admin)
                    .manualPull(
                        this.erc20Vault.address,
                        this.uniV3UpperVault.address,
                        [
                            BigNumber.from(10).pow(18).mul(1),
                            BigNumber.from(10).pow(18).mul(1),
                        ],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    );

                let prevBalances = [
                    await this.wsteth.balanceOf(this.erc20Vault.address),
                    await this.weth.balanceOf(this.erc20Vault.address),
                ];

                await this.subject
                    .connect(this.admin)
                    .manualPull(
                        this.erc20Vault.address,
                        this.uniV3UpperVault.address,
                        [
                            BigNumber.from(10).pow(18).mul(100),
                            BigNumber.from(10).pow(18).mul(100),
                        ],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    );

                let endBalances = [
                    await this.wsteth.balanceOf(this.erc20Vault.address),
                    await this.weth.balanceOf(this.erc20Vault.address),
                ];

                for (let j = 0; j < 2; ++j) {
                    expect(endBalances[j]).to.be.lt(prevBalances[j]);
                }
            });

            it("emits ManualPull event", async () => {
                await this.grantPermissions();
                await expect(
                    this.subject
                        .connect(this.admin)
                        .manualPull(
                            this.erc20Vault.address,
                            this.uniV3UpperVault.address,
                            [
                                BigNumber.from(10).pow(18).mul(1),
                                BigNumber.from(10).pow(18).mul(1),
                            ],
                            [ethers.constants.Zero, ethers.constants.Zero],
                            ethers.constants.MaxUint256
                        )
                ).to.emit(this.subject, "ManualPull");
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await this.grantPermissions();
                    await this.subject
                        .connect(this.admin)
                        .manualPull(
                            this.erc20Vault.address,
                            this.uniV3UpperVault.address,
                            [
                                BigNumber.from(10).pow(18).mul(1),
                                BigNumber.from(10).pow(18).mul(1),
                            ],
                            [ethers.constants.Zero, ethers.constants.Zero],
                            ethers.constants.MaxUint256
                        );
                });
                it("not allowed: operator", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .grantRole(
                                await this.subject.ADMIN_DELEGATE_ROLE(),
                                signer.address
                            );
                        await expect(
                            this.subject
                                .connect(signer)
                                .manualPull(
                                    this.erc20Vault.address,
                                    this.uniV3UpperVault.address,
                                    [
                                        BigNumber.from(10).pow(18).mul(1),
                                        BigNumber.from(10).pow(18).mul(1),
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).to.be.reverted;
                    });
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .manualPull(
                                    this.erc20Vault.address,
                                    this.uniV3UpperVault.address,
                                    [
                                        BigNumber.from(10).pow(18).mul(1),
                                        BigNumber.from(10).pow(18).mul(1),
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).to.be.reverted;
                    });
                });
            });
        });

        describe("#rebalanceUniV3Vaults", () => {
            beforeEach(async () => {
                this.grantPermissionsUniV3Vaults = async () => {
                    for (let vault of [
                        this.uniV3UpperVault,
                        this.uniV3LowerVault,
                    ]) {
                        let tokenId = await ethers.provider.send(
                            "eth_getStorageAt",
                            [
                                vault.address,
                                "0x4", // address of _nft
                            ]
                        );
                        await withSigner(
                            this.erc20RootVault.address,
                            async (erc20RootVaultSigner) => {
                                await this.vaultRegistry
                                    .connect(erc20RootVaultSigner)
                                    .approve(this.subject.address, tokenId);
                            }
                        );
                    }
                };
                this.drainLiquidity = async (vault: UniV3Vault) => {
                    let vaultNft = await vault.uniV3Nft();
                    await withSigner(vault.address, async (signer) => {
                        let [, , , , , , , liquidity, , , ,] =
                            await this.positionManager.positions(vaultNft);
                        await this.positionManager
                            .connect(signer)
                            .decreaseLiquidity({
                                tokenId: vaultNft,
                                liquidity: liquidity,
                                amount0Min: 0,
                                amount1Min: 0,
                                deadline: ethers.constants.MaxUint256,
                            });
                    });
                };
                this.calculateTvl = async () => {
                    const uniV3LowerTvl = (await this.uniV3LowerVault.tvl())[0];
                    const uniV3UpperTvl = (await this.uniV3UpperVault.tvl())[0];
                    return [
                        uniV3LowerTvl[0].add(uniV3LowerTvl[1]),
                        uniV3UpperTvl[0].add(uniV3UpperTvl[1]),
                    ];
                };
                await this.grantPermissions();
            });

            it("rebalances when delta is positive", async () => {
                this.semiPositionRange = 600;
                this.smallInt = 60;

                const currentTick = await this.getUniV3Tick();
                let tickLeftUpper =
                    currentTick
                        .div(this.smallInt)
                        .mul(this.smallInt)
                        .toNumber() + this.smallInt;
                let tickLeftLower = tickLeftUpper - 2 * this.semiPositionRange;

                let tickRightLower = tickLeftLower + this.semiPositionRange;
                let tickRightUpper = tickLeftUpper + this.semiPositionRange;

                await this.updateMockOracle(currentTick);

                await this.preparePush({
                    vault: this.uniV3LowerVault,
                    tickLower: tickLeftLower,
                    tickUpper: tickLeftUpper,
                });
                await this.preparePush({
                    vault: this.uniV3UpperVault,
                    tickLower: tickRightLower,
                    tickUpper: tickRightUpper,
                });

                await this.grantPermissionsUniV3Vaults();
                let [lowerVaultTvl, upperVaultTvl] = await this.calculateTvl();
                await expect(
                    this.subject
                        .connect(this.admin)
                        .rebalanceUniV3Vaults(
                            [ethers.constants.Zero, ethers.constants.Zero],
                            [ethers.constants.Zero, ethers.constants.Zero],
                            ethers.constants.MaxUint256
                        )
                ).to.not.be.reverted;
                let [newLowerVaultTvl, newUpperVaultTvl] =
                    await this.calculateTvl();
                expect(newLowerVaultTvl).to.be.lt(lowerVaultTvl);
                expect(newUpperVaultTvl).to.be.gt(upperVaultTvl);
            });
            it("rebalances when delta is negative", async () => {
                this.semiPositionRange = 600;
                this.smallInt = 60;

                const currentTick = await this.getUniV3Tick();
                let tickRightLower =
                    currentTick
                        .div(this.smallInt)
                        .mul(this.smallInt)
                        .toNumber() - this.smallInt;
                let tickRightUpper =
                    tickRightLower + 2 * this.semiPositionRange;

                let tickLeftLower = tickRightLower - this.semiPositionRange;
                let tickLeftUpper = tickRightUpper - this.semiPositionRange;

                await this.updateMockOracle(currentTick);

                await this.preparePush({
                    vault: this.uniV3LowerVault,
                    tickLower: tickLeftLower,
                    tickUpper: tickLeftUpper,
                });
                await this.preparePush({
                    vault: this.uniV3UpperVault,
                    tickLower: tickRightLower,
                    tickUpper: tickRightUpper,
                });

                await this.grantPermissionsUniV3Vaults();
                let [lowerVaultTvl, upperVaultTvl] = await this.calculateTvl();
                await expect(
                    this.subject
                        .connect(this.admin)
                        .rebalanceUniV3Vaults(
                            [ethers.constants.Zero, ethers.constants.Zero],
                            [ethers.constants.Zero, ethers.constants.Zero],
                            ethers.constants.MaxUint256
                        )
                ).to.not.be.reverted;
                let [newLowerVaultTvl, newUpperVaultTvl] =
                    await this.calculateTvl();
                expect(newLowerVaultTvl).to.be.gt(lowerVaultTvl);
                expect(newUpperVaultTvl).to.be.lt(upperVaultTvl);
            });
            it("rebalances when crossing the interval left to right", async () => {
                await this.preparePush({
                    vault: this.uniV3LowerVault,
                    tickLower: -800000,
                    tickUpper: -600000,
                });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await this.grantPermissionsUniV3Vaults();
                let [lowerVaultTvl, upperVaultTvl] = await this.calculateTvl();
                await expect(
                    this.subject
                        .connect(this.admin)
                        .rebalanceUniV3Vaults(
                            [ethers.constants.Zero, ethers.constants.Zero],
                            [ethers.constants.Zero, ethers.constants.Zero],
                            ethers.constants.MaxUint256
                        )
                ).to.not.be.reverted;
                let [newLowerVaultTvl, newUpperVaultTvl] =
                    await this.calculateTvl();
                expect(newLowerVaultTvl).to.be.lt(lowerVaultTvl);
                expect(newUpperVaultTvl).to.be.gt(upperVaultTvl);
            });
            it("swap vaults when crossing the interval left to right with no liquidity", async () => {
                await this.preparePush({
                    vault: this.uniV3LowerVault,
                    tickLower: -800000,
                    tickUpper: -600000,
                });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await this.grantPermissionsUniV3Vaults();
                await this.drainLiquidity(this.uniV3LowerVault);
                let result = await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceUniV3Vaults(
                        [ethers.constants.Zero, ethers.constants.Zero],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    );
                const pulledAmounts = result[0];
                const pushedAmounts = result[1];
                await this.subject
                    .connect(this.admin)
                    .rebalanceUniV3Vaults(
                        [ethers.constants.Zero, ethers.constants.Zero],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    );
                for (let i = 0; i < 2; ++i) {
                    expect(pulledAmounts[i]).to.be.equal(ethers.constants.Zero);
                    expect(pushedAmounts[i]).to.be.equal(ethers.constants.Zero);
                }
            });

            it("rebalances when crossing the interval right to left", async () => {
                await this.preparePush({
                    vault: this.uniV3LowerVault,
                    tickLower: 500000,
                    tickUpper: 700000,
                });
                await this.preparePush({
                    vault: this.uniV3UpperVault,
                    tickLower: 600000,
                    tickUpper: 800000,
                });
                await this.grantPermissionsUniV3Vaults();
                const result = await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceUniV3Vaults(
                        [ethers.constants.Zero, ethers.constants.Zero],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    );
                await expect(
                    this.subject
                        .connect(this.admin)
                        .rebalanceUniV3Vaults(
                            [ethers.constants.Zero, ethers.constants.Zero],
                            [ethers.constants.Zero, ethers.constants.Zero],
                            ethers.constants.MaxUint256
                        )
                ).to.not.be.reverted;
                const tvl = (await this.uniV3UpperVault.tvl())[0];
                for (let i = 0; i < 2; ++i) {
                    expect(tvl[i]).lt(BigNumber.from(10)); // check, that all liquidity passed to other vault
                }
            });

            it("swap vaults when crossing the interval right to left with no liquidity", async () => {
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await this.mockOracle.updatePrice(BigNumber.from(1).shl(95));
                await this.grantPermissionsUniV3Vaults();
                await this.drainLiquidity(this.uniV3UpperVault);
                const result = await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceUniV3Vaults(
                        [ethers.constants.Zero, ethers.constants.Zero],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    );
                const pulledAmounts = result[0];
                const pushedAmounts = result[1];
                await expect(
                    this.subject
                        .connect(this.admin)
                        .rebalanceUniV3Vaults(
                            [ethers.constants.Zero, ethers.constants.Zero],
                            [ethers.constants.Zero, ethers.constants.Zero],
                            ethers.constants.MaxUint256
                        )
                ).to.not.be.reverted;
                for (let i = 0; i < 2; ++i) {
                    expect(pulledAmounts[i]).to.be.equal(ethers.constants.Zero);
                    expect(pushedAmounts[i]).to.be.equal(ethers.constants.Zero);
                }
            });

            describe("edge cases:", () => {
                describe("when minLowerAmounts are more than actual", () => {
                    it("reverts", async () => {
                        await this.preparePush({ vault: this.uniV3LowerVault });
                        await this.preparePush({ vault: this.uniV3UpperVault });
                        await this.grantPermissionsUniV3Vaults();
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .rebalanceUniV3Vaults(
                                    [
                                        ethers.constants.MaxUint256,
                                        ethers.constants.MaxUint256,
                                    ],
                                    [
                                        ethers.constants.MaxUint256,
                                        ethers.constants.MaxUint256,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).to.be.reverted;
                    });
                });
                describe("when deadline is earlier than block timestamp", () => {
                    it("reverts", async () => {
                        await this.preparePush({ vault: this.uniV3LowerVault });
                        await this.preparePush({ vault: this.uniV3UpperVault });
                        await this.grantPermissionsUniV3Vaults();
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .rebalanceUniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.Zero
                                )
                        ).to.be.reverted;
                    });
                });
            });

            describe("access control:", () => {
                beforeEach(async () => {
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    await this.preparePush({ vault: this.uniV3UpperVault });
                    await this.grantPermissionsUniV3Vaults();
                });
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rebalanceUniV3Vaults(
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            )
                    ).to.not.be.reverted;
                });
                it("allowed: operator", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .grantRole(
                                await this.subject.ADMIN_DELEGATE_ROLE(),
                                signer.address
                            );
                        await expect(
                            this.subject
                                .connect(signer)
                                .rebalanceUniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).to.not.be.reverted;
                    });
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .rebalanceUniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).to.be.reverted;
                    });
                });
            });
        });

        describe("#rebalanceERC20UniV3Vaults", () => {
            beforeEach(async () => {
                this.calculateTvl = async () => {
                    const erc20Tvl = (await this.erc20Vault.tvl())[0];
                    const uniV3LowerTvl = (await this.uniV3LowerVault.tvl())[0];
                    const uniV3UpperTvl = (await this.uniV3UpperVault.tvl())[0];
                    return [
                        erc20Tvl[0].add(erc20Tvl[1]),
                        uniV3LowerTvl[0]
                            .add(uniV3LowerTvl[1])
                            .add(uniV3UpperTvl[0].add(uniV3UpperTvl[1])),
                    ];
                };
            });
            it("emits RebalancedErc20UniV3 event", async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await expect(
                    this.subject
                        .connect(this.admin)
                        .rebalanceERC20UniV3Vaults(
                            [ethers.constants.Zero, ethers.constants.Zero],
                            [ethers.constants.Zero, ethers.constants.Zero],
                            ethers.constants.MaxUint256
                        )
                ).to.emit(this.subject, "RebalancedErc20UniV3");
            });
            it("does nothing when capital delta is 0", async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
                let [erc20OverallTvl, uniV3OverallTvl] =
                    await this.calculateTvl();

                let clearValue = uniV3OverallTvl.div(20); // * 0.05 (erc20UniV3CapitalRatioD)

                await withSigner(this.erc20Vault.address, async (signer) => {
                    for (let token of [this.wsteth, this.weth]) {
                        await token
                            .connect(signer)
                            .transfer(
                                this.deployer.address,
                                BigNumber.from(10)
                                    .pow(18)
                                    .mul(500)
                                    .sub(clearValue.div(2))
                            );
                    }
                });

                [erc20OverallTvl, uniV3OverallTvl] = await this.calculateTvl();

                await this.subject
                    .connect(this.admin)
                    .rebalanceERC20UniV3Vaults(
                        [ethers.constants.Zero, ethers.constants.Zero],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    );

                expect(await this.calculateTvl()).to.be.deep.equal([
                    erc20OverallTvl,
                    uniV3OverallTvl,
                ]);
            });
            it("rebalances vaults when capital delta is not negative", async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });

                let [erc20OverallTvl, uniV3OverallTvl] =
                    await this.calculateTvl();

                await expect(
                    this.subject
                        .connect(this.admin)
                        .rebalanceERC20UniV3Vaults(
                            [ethers.constants.Zero, ethers.constants.Zero],
                            [ethers.constants.Zero, ethers.constants.Zero],
                            ethers.constants.MaxUint256
                        )
                ).to.not.be.reverted;

                let [newErc20OverallTvl, newUniV3OverallTvl] =
                    await this.calculateTvl();

                expect(newErc20OverallTvl).to.be.lt(erc20OverallTvl);
                expect(newUniV3OverallTvl).to.be.gt(uniV3OverallTvl);
            });
            it("rebalances vaults when capital delta is negative", async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await withSigner(this.erc20Vault.address, async (signer) => {
                    for (let token of [this.wsteth, this.weth]) {
                        await token
                            .connect(signer)
                            .transfer(
                                this.uniV3UpperVault.address,
                                BigNumber.from(10).pow(18).mul(500)
                            );
                    }
                });

                await this.subject.connect(this.admin).updateRatioParams({
                    erc20UniV3CapitalRatioD: BigNumber.from(10).pow(7).mul(5), // 0.05 * DENOMINATOR
                    erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5), // 0.5 * DENOMINATOR
                    minErc20UniV3CapitalRatioDeviationD:
                        BigNumber.from(10).pow(7),
                    minErc20TokenRatioDeviationD: BigNumber.from(10)
                        .pow(8)
                        .div(2),
                    minUniV3LiquidityRatioDeviationD: BigNumber.from(10)
                        .pow(8)
                        .div(2),
                });

                let [erc20OverallTvl, uniV3OverallTvl] =
                    await this.calculateTvl();

                for (let vault of [
                    this.uniV3LowerVault,
                    this.uniV3UpperVault,
                ]) {
                    let tokenId = await ethers.provider.send(
                        "eth_getStorageAt",
                        [
                            vault.address,
                            "0x4", // address of _nft
                        ]
                    );
                    await withSigner(
                        this.erc20RootVault.address,
                        async (erc20RootVaultSigner) => {
                            await this.vaultRegistry
                                .connect(erc20RootVaultSigner)
                                .approve(this.subject.address, tokenId);
                        }
                    );
                }

                await this.subject
                    .connect(this.admin)
                    .rebalanceERC20UniV3Vaults(
                        [ethers.constants.Zero, ethers.constants.Zero],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    );

                let [newErc20OverallTvl, newUniV3OverallTvl] =
                    await this.calculateTvl();

                expect(newErc20OverallTvl).to.be.gt(erc20OverallTvl);
                expect(newUniV3OverallTvl).to.be.lt(uniV3OverallTvl);
            });

            describe("edge cases:", () => {
                describe("when minLowerAmounts are more than actual", () => {
                    it("reverts", async () => {
                        await this.grantPermissions();
                        await this.preparePush({ vault: this.uniV3LowerVault });
                        await this.preparePush({ vault: this.uniV3UpperVault });
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .rebalanceERC20UniV3Vaults(
                                    [
                                        ethers.constants.MaxUint256,
                                        ethers.constants.MaxUint256,
                                    ],
                                    [
                                        ethers.constants.MaxUint256,
                                        ethers.constants.MaxUint256,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).to.be.reverted;
                    });
                });
                describe("when deadline is earlier than block timestamp", () => {
                    it("reverts", async () => {
                        await this.grantPermissions();
                        await this.preparePush({ vault: this.uniV3LowerVault });
                        await this.preparePush({ vault: this.uniV3UpperVault });
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .rebalanceERC20UniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.Zero
                                )
                        ).to.be.reverted;
                    });
                });
            });

            describe("access control:", () => {
                beforeEach(async () => {
                    await this.grantPermissions();
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    await this.preparePush({ vault: this.uniV3UpperVault });
                });

                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .rebalanceERC20UniV3Vaults(
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            )
                    ).to.not.be.reverted;
                });
                it("allowed: operator", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .grantRole(
                                await this.subject.ADMIN_DELEGATE_ROLE(),
                                signer.address
                            );
                        await expect(
                            this.subject
                                .connect(signer)
                                .rebalanceERC20UniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).to.not.be.reverted;
                    });
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .rebalanceERC20UniV3Vaults(
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    [
                                        ethers.constants.Zero,
                                        ethers.constants.Zero,
                                    ],
                                    ethers.constants.MaxUint256
                                )
                        ).to.be.reverted;
                    });
                });
            });
        });

        describe("#postPreOrder", () => {
            it("initializing preOrder when liquidityDelta is negative", async () => {
                await withSigner(this.erc20Vault.address, async (signer) => {
                    await this.wsteth
                        .connect(signer)
                        .transfer(
                            this.deployer.address,
                            BigNumber.from(10).pow(18).mul(500)
                        );
                });
                await this.subject.connect(this.admin).postPreOrder(0);
                await expect((await this.subject.preOrder()).tokenIn).eq(
                    this.weth.address
                );
                await expect((await this.subject.preOrder()).amountIn).eq(
                    BigNumber.from(10).pow(18).mul(250)
                );
            });
            it("initializing preOrder when liquidityDelta is not negative", async () => {
                await this.subject.connect(this.admin).postPreOrder(0);
                await expect((await this.subject.preOrder()).tokenIn).eq(
                    this.wsteth.address
                );
                await expect((await this.subject.preOrder()).amountIn).eq(
                    BigNumber.from(10).pow(18).mul(0)
                );
            });
            it("emits PreOrderPosted event", async () => {
                await expect(
                    this.subject.connect(this.admin).postPreOrder(0)
                ).to.emit(this.subject, "PreOrderPosted");
            });

            describe("edge cases:", () => {
                describe("when orderDeadline is lower than block.timestamp", () => {
                    it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                        await ethers.provider.send("hardhat_setStorageAt", [
                            this.subject.address,
                            "0x5", // address of orderDeadline
                            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                        ]);
                        await expect(
                            this.subject.connect(this.admin).postPreOrder(0)
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject.connect(this.admin).postPreOrder(0)
                    ).to.not.be.reverted;
                });
                it("allowed: operator", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .grantRole(
                                await this.subject.ADMIN_DELEGATE_ROLE(),
                                signer.address
                            );
                        await expect(
                            this.subject.connect(signer).postPreOrder(0)
                        ).to.not.be.reverted;
                    });
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).postPreOrder(0)
                        ).to.be.reverted;
                    });
                });
            });
        });

        describe("#signOrder", () => {
            beforeEach(async () => {
                this.successfulInitialization = async () => {
                    let kindSell =
                        "0xf3b277728b3fee749481eb3e0b3b48980dbbab78658fc419025cb16eee346775";
                    let balanceERC20 =
                        "0x5a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9";

                    await this.grantPermissions();
                    await this.subject.connect(this.admin).postPreOrder(0);
                    let preOrder = await this.subject.preOrder();
                    this.baseOrderStruct = {
                        sellToken: preOrder.tokenIn,
                        buyToken: preOrder.tokenOut,
                        receiver: this.erc20Vault.address,
                        sellAmount: preOrder.amountIn,
                        buyAmount: preOrder.minAmountOut,
                        validTo: preOrder.deadline,
                        appData: randomBytes(32),
                        feeAmount: BigNumber.from(500),
                        kind: kindSell,
                        partiallyFillable: false,
                        sellTokenBalance: balanceERC20,
                        buyTokenBalance: balanceERC20,
                    };
                };
            });
            it("signs order successfully when signed is set to true", async () => {
                await this.successfulInitialization();
                let orderHash = await this.cowswap.callStatic.hash(
                    this.baseOrderStruct,
                    await this.cowswap.domainSeparator()
                );
                let orderUuid = ethers.utils.solidityPack(
                    ["bytes32", "address", "uint32"],
                    [orderHash, randomBytes(20), randomBytes(4)]
                );
                await expect(
                    this.subject
                        .connect(this.admin)
                        .signOrder(this.baseOrderStruct, orderUuid, true)
                );
                expect(await this.subject.orderDeadline()).eq(
                    this.baseOrderStruct.validTo
                );
                expect(await this.cowswap.preSignature(orderUuid)).to.be.true;
            });
            it("resets order successfully when signed is set to false", async () => {
                await this.successfulInitialization();
                let orderHash = await this.cowswap.callStatic.hash(
                    this.baseOrderStruct,
                    await this.cowswap.domainSeparator()
                );
                let orderUuid = ethers.utils.solidityPack(
                    ["bytes32", "address", "uint32"],
                    [orderHash, randomBytes(20), randomBytes(4)]
                );
                await expect(
                    this.subject
                        .connect(this.admin)
                        .signOrder(this.baseOrderStruct, orderUuid, false)
                );
                expect(await this.cowswap.preSignature(orderUuid)).to.be.false;
            });
            it("emits OrderSigned event", async () => {
                await this.successfulInitialization();
                let orderHash = await this.cowswap.callStatic.hash(
                    this.baseOrderStruct,
                    await this.cowswap.domainSeparator()
                );
                await expect(
                    this.subject
                        .connect(this.admin)
                        .signOrder(
                            this.baseOrderStruct,
                            ethers.utils.solidityPack(
                                ["bytes32", "address", "uint32"],
                                [orderHash, randomBytes(20), randomBytes(4)]
                            ),
                            true
                        )
                ).to.emit(this.subject, "OrderSigned");
            });
            describe("edge cases:", () => {
                describe("when preorder deadline is earlier than block timestamp", () => {
                    it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                        await this.successfulInitialization();
                        let orderHash = await this.cowswap.callStatic.hash(
                            this.baseOrderStruct,
                            await this.cowswap.domainSeparator()
                        );
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [orderHash, randomBytes(20), randomBytes(4)]
                        );
                        await sleep(86400 * 100); // 100 days
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .signOrder(
                                    this.baseOrderStruct,
                                    orderUuid,
                                    true
                                )
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    });
                });
                describe("when order hash does not match with hash from uuid", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        await this.successfulInitialization();
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [randomBytes(32), randomBytes(20), randomBytes(4)]
                        );
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .signOrder(
                                    this.baseOrderStruct,
                                    orderUuid,
                                    true
                                )
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });
                describe("when order sell token does not match with preorder tokenIn", () => {
                    it(`reverts with ${Exceptions.INVALID_TOKEN}`, async () => {
                        await this.successfulInitialization();
                        let orderStruct = this.baseOrderStruct;
                        orderStruct.sellToken = this.usdc.address;
                        let orderHash = await this.cowswap.callStatic.hash(
                            orderStruct,
                            await this.cowswap.domainSeparator()
                        );
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [orderHash, randomBytes(20), randomBytes(4)]
                        );
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .signOrder(orderStruct, orderUuid, true)
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    });
                });
                describe("when order buy token does not match with preorder tokenOut", () => {
                    it(`reverts with ${Exceptions.INVALID_TOKEN}`, async () => {
                        await this.successfulInitialization();
                        let orderStruct = this.baseOrderStruct;
                        orderStruct.buyToken = this.wsteth.address;
                        let orderHash = await this.cowswap.callStatic.hash(
                            orderStruct,
                            await this.cowswap.domainSeparator()
                        );
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [orderHash, randomBytes(20), randomBytes(4)]
                        );
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .signOrder(orderStruct, orderUuid, true)
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    });
                });
                describe("when order sell amount does not equal to preorder amountIn", () => {
                    it(`reverts with ${Exceptions.INVALID_VALUE}`, async () => {
                        await this.successfulInitialization();
                        let orderStruct = this.baseOrderStruct;
                        orderStruct.sellAmount = ethers.constants.MaxUint256;
                        let orderHash = await this.cowswap.callStatic.hash(
                            orderStruct,
                            await this.cowswap.domainSeparator()
                        );
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [orderHash, randomBytes(20), randomBytes(4)]
                        );
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .signOrder(orderStruct, orderUuid, true)
                        ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                    });
                });
                describe("when reciever address is not erc20Vault", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await this.successfulInitialization();
                        let orderStruct = this.baseOrderStruct;
                        orderStruct.receiver = this.deployer.address;
                        let orderHash = await this.cowswap.callStatic.hash(
                            orderStruct,
                            await this.cowswap.domainSeparator()
                        );
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [orderHash, randomBytes(20), randomBytes(4)]
                        );
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .signOrder(orderStruct, orderUuid, true)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
                describe("when order buy amount is less than minAmountOut", () => {
                    it(`reverts with ${Exceptions.LIMIT_UNDERFLOW}`, async () => {
                        await withSigner(
                            this.erc20Vault.address,
                            async (signer) => {
                                await this.wsteth
                                    .connect(signer)
                                    .transfer(
                                        this.deployer.address,
                                        BigNumber.from(10).pow(18).mul(500)
                                    );
                            }
                        );
                        await this.successfulInitialization();
                        let orderStruct = this.baseOrderStruct;
                        orderStruct.buyAmount = ethers.constants.Zero;
                        let orderHash = await this.cowswap.callStatic.hash(
                            orderStruct,
                            await this.cowswap.domainSeparator()
                        );
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [orderHash, randomBytes(20), randomBytes(4)]
                        );
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .signOrder(orderStruct, orderUuid, true)
                        ).to.be.revertedWith(Exceptions.LIMIT_UNDERFLOW);
                    });
                });
                describe("when validTo is later than deadline", () => {
                    it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                        await this.successfulInitialization();
                        let orderStruct = this.baseOrderStruct;
                        orderStruct.validTo = BigNumber.from(1).shl(32).sub(1);
                        let orderHash = await this.cowswap.callStatic.hash(
                            orderStruct,
                            await this.cowswap.domainSeparator()
                        );
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [orderHash, randomBytes(20), randomBytes(4)]
                        );
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .signOrder(orderStruct, orderUuid, true)
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await this.successfulInitialization();
                    let orderHash = await this.cowswap.callStatic.hash(
                        this.baseOrderStruct,
                        await this.cowswap.domainSeparator()
                    );
                    let orderUuid = ethers.utils.solidityPack(
                        ["bytes32", "address", "uint32"],
                        [orderHash, randomBytes(20), randomBytes(4)]
                    );
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .signOrder(this.baseOrderStruct, orderUuid, true)
                    ).to.not.be.reverted;
                });
                it("allowed: operator", async () => {
                    await this.successfulInitialization();
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .grantRole(
                                await this.subject.ADMIN_DELEGATE_ROLE(),
                                signer.address
                            );
                        let orderHash = await this.cowswap.callStatic.hash(
                            this.baseOrderStruct,
                            await this.cowswap.domainSeparator()
                        );
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [orderHash, randomBytes(20), randomBytes(4)]
                        );
                        await expect(
                            this.subject
                                .connect(signer)
                                .signOrder(
                                    this.baseOrderStruct,
                                    orderUuid,
                                    true
                                )
                        ).to.not.be.reverted;
                    });
                });
                it("not allowed: any address", async () => {
                    await this.successfulInitialization();
                    await withSigner(randomAddress(), async (signer) => {
                        let orderHash = await this.cowswap.callStatic.hash(
                            this.baseOrderStruct,
                            await this.cowswap.domainSeparator()
                        );
                        let orderUuid = ethers.utils.solidityPack(
                            ["bytes32", "address", "uint32"],
                            [orderHash, randomBytes(20), randomBytes(4)]
                        );
                        await expect(
                            this.subject
                                .connect(signer)
                                .signOrder(
                                    this.baseOrderStruct,
                                    orderUuid,
                                    true
                                )
                        ).to.be.reverted;
                    });
                });
            });
        });

        describe("#depositCallback", () => {
            it("calls rebalance inside", async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await expect(this.subject.connect(this.admin).depositCallback())
                    .to.not.be.reverted;
            });
            describe("access control:", () => {
                beforeEach(async () => {
                    await this.grantPermissions();
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    await this.preparePush({ vault: this.uniV3UpperVault });
                });

                it("allowed: admin", async () => {
                    await expect(
                        this.subject.connect(this.admin).depositCallback()
                    ).to.not.be.reverted;
                });
                it("allowed: operator", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .grantRole(
                                await this.subject.ADMIN_DELEGATE_ROLE(),
                                signer.address
                            );
                        await expect(
                            this.subject.connect(signer).depositCallback()
                        ).to.not.be.reverted;
                    });
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).depositCallback()
                        ).to.be.reverted;
                    });
                });
            });
        });
        describe("#withdrawCallback", () => {
            it("calls rebalance inside", async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await expect(
                    this.subject.connect(this.admin).withdrawCallback()
                ).to.not.be.reverted;
            });
            describe("access control:", () => {
                beforeEach(async () => {
                    await this.grantPermissions();
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    await this.preparePush({ vault: this.uniV3UpperVault });
                });

                it("allowed: admin", async () => {
                    await expect(
                        this.subject.connect(this.admin).withdrawCallback()
                    ).to.not.be.reverted;
                });
                it("allowed: operator", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await this.subject
                            .connect(this.admin)
                            .grantRole(
                                await this.subject.ADMIN_DELEGATE_ROLE(),
                                signer.address
                            );
                        await expect(
                            this.subject.connect(signer).withdrawCallback()
                        ).to.not.be.reverted;
                    });
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).withdrawCallback()
                        ).to.be.reverted;
                    });
                });
            });
        });
    });
    describe("#depositCallback", () => {
        it("calls rebalance inside", async () => {
            await this.grantPermissions();
            await this.preparePush({ vault: this.uniV3LowerVault });
            await this.preparePush({ vault: this.uniV3UpperVault });
            await expect(this.subject.connect(this.admin).depositCallback()).to
                .not.be.reverted;
        });
        describe("access control:", () => {
            beforeEach(async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
            });

            it("allowed: admin", async () => {
                await expect(this.subject.connect(this.admin).depositCallback())
                    .to.not.be.reverted;
            });
            it("allowed: operator", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject
                        .connect(this.admin)
                        .grantRole(
                            await this.subject.ADMIN_DELEGATE_ROLE(),
                            signer.address
                        );
                    await expect(this.subject.connect(signer).depositCallback())
                        .to.not.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).depositCallback())
                        .to.be.reverted;
                });
            });
        });
    });
    describe("#withdrawCallback", () => {
        it("calls rebalance inside", async () => {
            await this.grantPermissions();
            await this.preparePush({ vault: this.uniV3LowerVault });
            await this.preparePush({ vault: this.uniV3UpperVault });
            await expect(this.subject.connect(this.admin).withdrawCallback()).to
                .not.be.reverted;
        });
        describe("access control:", () => {
            beforeEach(async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
            });

            it("allowed: admin", async () => {
                await expect(
                    this.subject.connect(this.admin).withdrawCallback()
                ).to.not.be.reverted;
            });
            it("allowed: operator", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject
                        .connect(this.admin)
                        .grantRole(
                            await this.subject.ADMIN_DELEGATE_ROLE(),
                            signer.address
                        );
                    await expect(
                        this.subject.connect(signer).withdrawCallback()
                    ).to.not.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject.connect(signer).withdrawCallback()
                    ).to.be.reverted;
                });
            });
        });
    });
});
