import { expect } from "chai";
import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";

import { contract } from "./library/setup";
import {
    ERC20Vault,
    LStrategy,
    LStrategyOrderHelper,
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

type CustomContext = {
    uniV3LowerVault: UniV3Vault;
    uniV3UpperVault: UniV3Vault;
    erc20Vault: ERC20Vault;
    cowswap: MockCowswap;
    mockOracle: MockOracle;
    orderHelper: LStrategyOrderHelper;
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

                await setupVault(
                    hre,
                    uniV3LowerVaultNft,
                    "UniV3VaultGovernance",
                    {
                        createVaultArgs: [
                            tokens,
                            this.deployer.address,
                            uniV3PoolFee,
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

                let strategyOrderHelper = await deploy("LStrategyOrderHelper", {
                    from: this.deployer.address,
                    contract: "LStrategyOrderHelper",
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
                        strategyOrderHelper.address,
                        this.admin.address,
                    ],
                    log: true,
                    autoMine: true,
                });

                this.orderHelper = await ethers.getContractAt(
                    "LStrategyOrderHelper",
                    strategyOrderHelper.address
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

                await wsteth.transfer(
                    this.subject.address,
                    BigNumber.from(10).pow(18).mul(3)
                );

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
                    oracleSafety: 5,
                    minRebalanceWaitTime: 86400,
                    orderDeadline: 86400 * 30,
                    oracle: oracleDeployParams.address,
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

    describe("#updateTradingParams", () => {
        beforeEach(async () => {
            this.baseParams = {
                maxSlippageD: BigNumber.from(10).pow(6),
                minRebalanceWaitTime: 86400,
                orderDeadline: 86400 * 30,
                oracleSafety: 5,
                oracle: this.mellowOracle.address,
            };
        });

        it("updates trading params", async () => {
            await this.subject
                .connect(this.admin)
                .updateTradingParams(this.baseParams);
            const expectedParams = [
                BigNumber.from(10).pow(6),
                BigNumber.from(86400),
                86400 * 30,
                5,
                this.mellowOracle.address,
            ];
            const returnedParams = await this.subject.tradingParams();
            expect(expectedParams == returnedParams);
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
            describe("when oracleSafety is incorrect", () => {
                it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                    let params = this.baseParams;
                    params.oracleSafety = 228;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .updateTradingParams(params)
                    ).to.be.revertedWith(Exceptions.INVARIANT);
                });
            });
            describe("when minRebalanceWaitTime is more than 30 days", () => {
                it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                    let params = this.baseParams;
                    params.minRebalanceWaitTime = 86400 * 31;
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
                minErc20UniV3CapitalRatioDeviationD: BigNumber.from(10).pow(7),
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
            expect(await this.subject.ratioParams()).to.be.eqls(expectedParams);
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
                    params.erc20TokenRatioD = BigNumber.from(10).pow(9).mul(2);
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
            const expectedParams = [
                100,
                BigNumber.from(10).pow(6),
                BigNumber.from(10).pow(6),
                BigNumber.from(86400 * 30),
            ];
            const returnedParams = await this.subject.otherParams();
            expect(expectedParams == returnedParams);
        });
        it("emits OtherParamsUpdated event", async () => {
            await expect(
                this.subject
                    .connect(this.admin)
                    .updateOtherParams(this.baseParams)
            ).to.emit(this.subject, "OtherParamsUpdated");
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
                minRebalanceWaitTime: 86400,
                orderDeadline: 86400 * 30,
                oracleSafety: 1,
                oracle: this.mockOracle.address,
            };
            expect(
                (
                    await this.subject.targetPrice(
                        [this.wsteth.address, this.weth.address],
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
                        minRebalanceWaitTime: 86400,
                        orderDeadline: 86400 * 30,
                        oracleSafety: 1,
                        oracle: ethers.constants.AddressZero,
                    };
                    await expect(
                        this.subject.targetPrice(
                            [this.wsteth.address, this.weth.address],
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
                    const result = await this.subject.targetUniV3LiquidityRatio(
                        1
                    );
                    expect(result.isNegative).to.be.false;
                    expect(result.liquidityRatioD).to.be.equal(
                        BigNumber.from(10).pow(9).div(887220)
                    );
                });
            });
            describe("when target tick is less, than mid tick", () => {
                it("returns isNegative true", async () => {
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    const result = await this.subject.targetUniV3LiquidityRatio(
                        -1
                    );
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
                    .approve(this.cowswap.address, BigNumber.from(10).pow(18));
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
                    this.subject.connect(this.admin).resetCowswapAllowance(0)
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
                        this.subject.connect(signer).resetCowswapAllowance(0)
                    ).to.not.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await this.grantPermissions();
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject.connect(signer).resetCowswapAllowance(0)
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
            for (let i = 0; i < 2; ++i) {
                lowerVaultFees[i].add(upperVaultFees[i]);
            }
            let sumFees = await this.subject
                .connect(this.admin)
                .callStatic.collectUniFees();
            expect(sumFees == lowerVaultFees);
            await expect(this.subject.connect(this.admin).collectUniFees()).to
                .not.be.reverted;
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
                    expect(
                        sumFees ==
                            [ethers.constants.Zero, ethers.constants.Zero]
                    );
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
                await expect(this.subject.connect(this.admin).collectUniFees())
                    .to.not.be.reverted;
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
                    await expect(this.subject.connect(signer).collectUniFees())
                        .to.not.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).collectUniFees())
                        .to.be.reverted;
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
        });

        it("pulls tokens from one vault to another", async () => {
            await this.grantPermissions();
            await this.subject
                .connect(this.admin)
                .manualPull(
                    this.erc20Vault.address,
                    this.uniV3UpperVault.address,
                    [
                        BigNumber.from(10).pow(18).mul(3000),
                        BigNumber.from(10).pow(18).mul(3000),
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
                    await this.wsteth.balanceOf(this.uniV3UpperVault.address),
                    await this.weth.balanceOf(this.uniV3UpperVault.address),
                ],
            ];
            expect(
                endBalances ==
                    [
                        [
                            BigNumber.from(10).pow(18).mul(6000),
                            BigNumber.from(10).pow(18).mul(6000),
                        ],
                        [ethers.constants.Zero, ethers.constants.Zero],
                    ]
            );
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
                                [ethers.constants.Zero, ethers.constants.Zero],
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
                                [ethers.constants.Zero, ethers.constants.Zero],
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
            await this.preparePush({ vault: this.uniV3LowerVault });
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
            expect(
                newLowerVaultTvl.lt(lowerVaultTvl) &&
                    newUpperVaultTvl.gt(upperVaultTvl)
            );
        });
        it("rebalances when delta is negative", async () => {
            await this.preparePush({
                vault: this.uniV3LowerVault,
                tickLower: -1000,
                tickUpper: 1000,
            });
            await this.preparePush({
                vault: this.uniV3UpperVault,
                tickLower: -1000,
                tickUpper: 1000,
            });
            await this.mockOracle.updatePrice(
                BigNumber.from(1).shl(96).mul(110).div(100)
            );
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
            expect(
                newLowerVaultTvl.gt(lowerVaultTvl) &&
                    newUpperVaultTvl.lt(upperVaultTvl)
            );
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
            expect(
                newLowerVaultTvl.lt(lowerVaultTvl) &&
                    newUpperVaultTvl.gt(upperVaultTvl)
            );
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
            await this.subject
                .connect(this.admin)
                .rebalanceUniV3Vaults(
                    [ethers.constants.Zero, ethers.constants.Zero],
                    [ethers.constants.Zero, ethers.constants.Zero],
                    ethers.constants.MaxUint256
                );
            for (let i = 0; i < 2; ++i) {
                for (let j = 0; j < 2; ++j) {
                    expect(result[i][j]).equal(ethers.constants.Zero);
                }
            }
        });
        it("rebalances when crossing the interval right to left", async () => {
            await this.preparePush({ vault: this.uniV3LowerVault });
            await this.preparePush({ vault: this.uniV3UpperVault });
            await this.mockOracle.updatePrice(BigNumber.from(1).shl(95));
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
                for (let j = 0; j < 2; ++j) {
                    expect(result[i][j]).equal(ethers.constants.Zero);
                }
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
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
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
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
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
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
                                ethers.constants.MaxUint256
                            )
                    ).to.be.reverted;
                });
            });
        });
    });

    describe("#rebalanceERC20UniV3Vaults", () => {
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
            let [erc20OverallTvl, uniV3OverallTvl] = await this.calculateTvl();

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

            let [erc20OverallTvl, uniV3OverallTvl] = await this.calculateTvl();

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

            expect(
                newErc20OverallTvl.lt(erc20OverallTvl) &&
                    newUniV3OverallTvl.gt(uniV3OverallTvl)
            );
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
                minErc20UniV3CapitalRatioDeviationD: BigNumber.from(10).pow(7),
                minErc20TokenRatioDeviationD: BigNumber.from(10).pow(8).div(2),
                minUniV3LiquidityRatioDeviationD: BigNumber.from(10)
                    .pow(8)
                    .div(2),
            });

            let [erc20OverallTvl, uniV3OverallTvl] = await this.calculateTvl();

            for (let vault of [this.uniV3LowerVault, this.uniV3UpperVault]) {
                let tokenId = await ethers.provider.send("eth_getStorageAt", [
                    vault.address,
                    "0x4", // address of _nft
                ]);
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

            expect(
                newErc20OverallTvl.gt(erc20OverallTvl) &&
                    newUniV3OverallTvl.lt(uniV3OverallTvl)
            );
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
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
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
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
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
                                [ethers.constants.Zero, ethers.constants.Zero],
                                [ethers.constants.Zero, ethers.constants.Zero],
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
            await this.subject.connect(this.admin).postPreOrder();
            await expect((await this.subject.preOrder()).tokenIn).eq(
                this.weth.address
            );
            await expect((await this.subject.preOrder()).amountIn).eq(
                BigNumber.from(10).pow(18).mul(250)
            );
        });
        it("initializing preOrder when liquidityDelta is not negative", async () => {
            await this.subject.connect(this.admin).postPreOrder();
            await expect((await this.subject.preOrder()).tokenIn).eq(
                this.wsteth.address
            );
            await expect((await this.subject.preOrder()).amountIn).eq(
                BigNumber.from(10).pow(18).mul(0)
            );
        });
        it("emits PreOrderPosted event", async () => {
            await expect(
                this.subject.connect(this.admin).postPreOrder()
            ).to.emit(this.subject, "PreOrderPosted");
        });

        describe("edge cases:", () => {
            describe("when orderDeadline is lower than block.timestamp", () => {
                it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                    await ethers.provider.send("hardhat_setStorageAt", [
                        this.subject.address,
                        "0x6", // address of orderDeadline
                        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                    ]);
                    await expect(
                        this.subject.connect(this.admin).postPreOrder()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });

        describe("access control:", () => {
            it("allowed: admin", async () => {
                await expect(this.subject.connect(this.admin).postPreOrder()).to
                    .not.be.reverted;
            });
            it("allowed: operator", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject
                        .connect(this.admin)
                        .grantRole(
                            await this.subject.ADMIN_DELEGATE_ROLE(),
                            signer.address
                        );
                    await expect(this.subject.connect(signer).postPreOrder()).to
                        .not.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).postPreOrder()).to
                        .be.reverted;
                });
            });
        });
    });

    describe("#signOrder", () => {
        beforeEach(async () => {
            this.successfulInitialization = async () => {
                await this.grantPermissions();
                await this.subject.connect(this.admin).postPreOrder();
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
                    kind: randomBytes(32),
                    partiallyFillable: false,
                    sellTokenBalance: randomBytes(32),
                    buyTokenBalance: randomBytes(32),
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
                            .signOrder(this.baseOrderStruct, orderUuid, true)
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
                            .signOrder(this.baseOrderStruct, orderUuid, true)
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
                            .signOrder(this.baseOrderStruct, orderUuid, true)
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
                            .signOrder(this.baseOrderStruct, orderUuid, true)
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
            await expect(
                this.subject
                    .connect(this.admin)
                    .depositCallback()
            ).to.emit(this.subject, "RebalancedErc20UniV3");
        });
        describe("access control:", () => {
            beforeEach(async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
            });

            it("allowed: admin", async () => {
                await expect(this.subject.connect(this.admin).depositCallback()).to
                    .not.be.reverted;
            });
            it("allowed: operator", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject
                        .connect(this.admin)
                        .grantRole(
                            await this.subject.ADMIN_DELEGATE_ROLE(),
                            signer.address
                        );
                    await expect(this.subject.connect(signer).depositCallback()).to
                        .not.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).depositCallback()).to
                        .be.reverted;
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
                this.subject
                    .connect(this.admin)
                    .withdrawCallback()
            ).to.emit(this.subject, "RebalancedErc20UniV3");
        });
        describe("access control:", () => {
            beforeEach(async () => {
                await this.grantPermissions();
                await this.preparePush({ vault: this.uniV3LowerVault });
                await this.preparePush({ vault: this.uniV3UpperVault });
            });

            it("allowed: admin", async () => {
                await expect(this.subject.connect(this.admin).withdrawCallback()).to
                    .not.be.reverted;
            });
            it("allowed: operator", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject
                        .connect(this.admin)
                        .grantRole(
                            await this.subject.ADMIN_DELEGATE_ROLE(),
                            signer.address
                        );
                    await expect(this.subject.connect(signer).withdrawCallback()).to
                        .not.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).withdrawCallback()).to
                        .be.reverted;
                });
            });
        });
    });
});
