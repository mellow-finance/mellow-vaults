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
import { ERC20, IERC20 } from "./library/Types";
import { randomBytes } from "ethers/lib/utils";
import { TickMath } from "@uniswap/v3-sdk";
import { sqrt } from "@uniswap/sdk-core";
import JSBI from "jsbi";

type CustomContext = {
    uniV3LowerVault: UniV3Vault;
    uniV3UpperVault: UniV3Vault;
    erc20Vault: ERC20Vault;
    cowswap: MockCowswap;
    mockOracle: MockOracle;
    orderHelper: LStrategyHelper;
};

type DeployOptions = {};

contract<LStrategy, DeployOptions, CustomContext>(
    "LStrategy_SpotPriceAttack",
    function () {
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
                    };

                    this.swapTokens = async (
                        senderAddress: string,
                        recipientAddress: string,
                        tokenIn: ERC20,
                        tokenOut: ERC20,
                        amountIn: BigNumber
                    ) => {
                        await withSigner(
                            senderAddress,
                            async (senderSigner) => {
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
                            }
                        );
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
                        wethAmount = BigNumber.from(10).pow(12),
                        wstethAmount = BigNumber.from(10).pow(12),
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
                        const result =
                            await this.positionManager.callStatic.mint(
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
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitPermissionGrants(this.wsteth.address);

                    const tokens = [this.weth.address, this.wsteth.address]
                        .map((t) => t.toLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let uniV3LowerVaultNft = startNft;
                    let uniV3UpperVaultNft = startNft + 1;
                    let erc20VaultNft = startNft + 2;
                    let uniV3Helper = (await ethers.getContract("UniV3Helper"))
                        .address;
                    await setupVault(
                        hre,
                        uniV3LowerVaultNft,
                        "UniV3VaultSpotGovernance",
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
                        "UniV3VaultSpotGovernance",
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
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

                    const { deploy } = deployments;
                    let cowswapDeployParams = await deploy("MockCowswap", {
                        from: this.deployer.address,
                        contract: "MockCowswap",
                        args: [],
                        log: true,
                        autoMine: true,
                    });

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
                            cowswapDeployParams.address,
                            this.erc20Vault.address,
                            this.uniV3LowerVault.address,
                            this.uniV3UpperVault.address,
                            strategyHelper.address,
                            this.admin.address,
                            120,
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

                    await this.erc20RootVault
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

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
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
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
                    this.steth = steth;

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
                    const options = {
                        value: BigNumber.from(10).pow(18).mul(2000),
                    };
                    await curvePool.exchange(
                        0,
                        1,
                        BigNumber.from(10).pow(18).mul(2000),
                        ethers.constants.Zero,
                        options
                    );
                    await wsteth.wrap(BigNumber.from(10).pow(18).mul(1999));

                    await wsteth.transfer(
                        this.subject.address,
                        BigNumber.from(10).pow(18).mul(3)
                    );

                    this.mintFunds = async (base: BigNumber) => {
                        const weth = await ethers.getContractAt(
                            IWETH,
                            this.weth.address
                        );

                        const wsteth = await ethers.getContractAt(
                            IWSTETH,
                            this.wsteth.address
                        );

                        await mint(
                            "WETH",
                            this.subject.address,
                            base.mul(4000)
                        );
                        await mint(
                            "WETH",
                            this.deployer.address,
                            base.mul(4000)
                        );

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
                        await wsteth.transfer(
                            this.subject.address,
                            base.mul(3)
                        );
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

                    await this.uniV3VaultSpotGovernance
                        .connect(this.admin)
                        .stageDelayedProtocolParams({
                            positionManager: uniswapV3PositionManager,
                            oracle: oracleDeployParams.address,
                        });
                    await sleep(86400);
                    await this.uniV3VaultSpotGovernance
                        .connect(this.admin)
                        .commitDelayedProtocolParams();

                    await this.subject.connect(this.admin).updateTradingParams({
                        oracle: oracleDeployParams.address,
                        maxSlippageD: BigNumber.from(10).pow(7),
                        oracleSafetyMask: 0x20,
                        orderDeadline: 86400 * 30,
                        maxFee0: BigNumber.from(10).pow(9),
                        maxFee1: BigNumber.from(10).pow(9),
                    });

                    await this.subject.connect(this.admin).updateRatioParams({
                        erc20UniV3CapitalRatioD: BigNumber.from(10)
                            .pow(7)
                            .mul(5), // 0.05 * DENOMINATOR
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
                        minToken0ForOpening: BigNumber.from(10).pow(6),
                        minToken1ForOpening: BigNumber.from(10).pow(6),
                        secondsBetweenRebalances: BigNumber.from(10).pow(6),
                    });

                    this.swapTokens = async (
                        senderAddress: string,
                        recipientAddress: string,
                        tokenIn: ERC20,
                        tokenOut: ERC20,
                        amountIn: BigNumber
                    ) => {
                        await withSigner(
                            senderAddress,
                            async (senderSigner) => {
                                await tokenIn
                                    .connect(senderSigner)
                                    .approve(
                                        this.swapRouter.address,
                                        ethers.constants.MaxUint256
                                    );
                                let params = {
                                    tokenIn: tokenIn.address,
                                    tokenOut: tokenOut.address,
                                    fee: 500,
                                    recipient: recipientAddress,
                                    deadline: ethers.constants.MaxUint256,
                                    amountIn: amountIn,
                                    amountOutMinimum: 0,
                                    sqrtPriceLimitX96: 0,
                                };
                                await this.swapRouter
                                    .connect(senderSigner)
                                    .exactInputSingle(params);
                            }
                        );
                    };

                    this.makeDesiredPoolPrice = async (
                        tick: BigNumber,
                        user: string
                    ) => {
                        let lowerVault = await ethers.getContractAt(
                            "IUniV3Vault",
                            await this.subject.lowerVault()
                        );
                        let pool = await ethers.getContractAt(
                            "IUniswapV3Pool",
                            await lowerVault.pool()
                        );
                        let startTry = BigNumber.from(10).pow(17).mul(60);

                        let needIncrease = 0; //mock initialization

                        while (true) {
                            let currentPoolState = await pool.slot0();
                            let currentPoolTick = BigNumber.from(
                                currentPoolState.tick
                            );

                            if (currentPoolTick.eq(tick)) {
                                break;
                            }

                            if (currentPoolTick.lt(tick)) {
                                if (needIncrease == 0) {
                                    needIncrease = 1;
                                    startTry = startTry.div(2);
                                }
                                await this.swapTokens(
                                    user,
                                    user,
                                    this.weth,
                                    this.wsteth,
                                    startTry
                                );
                            } else {
                                if (needIncrease == 1) {
                                    needIncrease = 0;
                                    startTry = startTry.div(2);
                                }
                                await this.swapTokens(
                                    user,
                                    user,
                                    this.wsteth,
                                    this.weth,
                                    startTry
                                );
                            }
                        }
                    };

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#attack scenario", () => {
            //open initial positions of equal size and some ticks
            beforeEach(async () => {
                for (let vault of [
                    this.uniV3UpperVault,
                    this.uniV3LowerVault,
                ]) {
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

                this.mintTokensForUser = async (
                    wethCapital: BigNumber,
                    user: string
                ) => {
                    await withSigner(randomAddress(), async (signer) => {
                        const minAmount = wethCapital;
                        await mint("WETH", signer.address, minAmount);
                        await this.weth
                            .connect(signer)
                            .approve(
                                this.curvePool.address,
                                ethers.constants.MaxUint256
                            );
                        await this.steth
                            .connect(signer)
                            .approve(
                                this.wsteth.address,
                                ethers.constants.MaxUint256
                            );
                        const weth = await ethers.getContractAt(
                            IWETH,
                            this.weth.address
                        );
                        await weth.connect(signer).withdraw(minAmount.div(2));
                        const options = { value: minAmount.div(2) };
                        await this.curvePool
                            .connect(signer)
                            .exchange(
                                0,
                                1,
                                minAmount.div(2),
                                ethers.constants.Zero,
                                options
                            );

                        const wsteth = await ethers.getContractAt(
                            IWSTETH,
                            this.wsteth.address
                        );
                        await wsteth
                            .connect(signer)
                            .wrap(minAmount.div(2).mul(199).div(200));

                        const wethAmount = await this.weth.balanceOf(
                            signer.address
                        );
                        const wstethAmount = await this.wsteth.balanceOf(
                            signer.address
                        );

                        await this.weth
                            .connect(signer)
                            .transfer(user, wethAmount);
                        await this.wsteth
                            .connect(signer)
                            .transfer(user, wstethAmount);
                    });
                };

                this.makeDepositFromRandomAddress = async (
                    wethCapital: BigNumber
                ) => {
                    await withSigner(randomAddress(), async (signer) => {
                        await this.erc20RootVault
                            .connect(this.admin)
                            .addDepositorsToAllowlist([signer.address]);
                        await this.mintTokensForUser(
                            wethCapital,
                            signer.address
                        );

                        const token0Amount = await this.wsteth.balanceOf(
                            signer.address
                        );
                        const token1Amount = await this.weth.balanceOf(
                            signer.address
                        );

                        await this.wsteth
                            .connect(signer)
                            .approve(this.erc20RootVault.address, token0Amount);
                        await this.weth
                            .connect(signer)
                            .approve(this.erc20RootVault.address, token1Amount);

                        await this.erc20RootVault
                            .connect(signer)
                            .deposit([token0Amount, token1Amount], 0, []);
                    });
                };

                // dust for inital deposit
                await this.makeDepositFromRandomAddress(
                    BigNumber.from(10).pow(9).mul(100)
                );

                // total deposit of all users on the vault
                await this.makeDepositFromRandomAddress(
                    BigNumber.from(10).pow(18).mul(2000)
                );

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
                    minErc20UniV3CapitalRatioDeviationD:
                        BigNumber.from(10).pow(5),
                    minErc20TokenRatioDeviationD: BigNumber.from(10)
                        .pow(8)
                        .div(2),
                    minUniV3LiquidityRatioDeviationD: BigNumber.from(10)
                        .pow(7)
                        .div(2),
                });

                await this.subject.connect(this.admin).updateOtherParams({
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    secondsBetweenRebalances: BigNumber.from(0),
                });

                {
                    // rebalance vaults by LStrategy:
                    await this.subject
                        .connect(this.admin)
                        .rebalanceERC20UniV3Vaults(
                            [0, 0],
                            [0, 0],
                            ethers.constants.MaxUint256
                        );
                    await this.subject
                        .connect(this.admin)
                        .rebalanceUniV3Vaults(
                            [0, 0],
                            [0, 0],
                            ethers.constants.MaxUint256
                        );
                }
            });

            describe.only("deposit, move price, withdraw, price moves back [by arbitrageurs]", () => {
                it("works", async () => {
                    console.log((await this.erc20Vault.tvl())[0]);
                    console.log((await this.uniV3LowerVault.tvl())[0]);
                    console.log((await this.uniV3UpperVault.tvl())[0]);
                });
            });

            describe("deposit, move price, withdraw, move price back", () => {
                it("works", async () => {});
            });

            describe("move price, deposit, prices moves back [by arbitrageurs], withdraw", () => {
                it("works", async () => {});
            });

            describe("move price, deposit, move price back, withdraw", () => {
                it("works", async () => {});
            });
        });
    }
);
