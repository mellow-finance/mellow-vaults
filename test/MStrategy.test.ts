import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    now,
    randomAddress,
    sleep,
    toObject,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    MStrategy,
    ProtocolGovernance,
    IYearnProtocolVault,
    MockNonfungiblePositionManager,
    MockUniswapV3Factory,
    MockUniswapV3Pool,
} from "./types";
import {
    setupVault,
    combineVaults,
    PermissionIdsLibrary,
} from "./../deploy/0000_utils";
import { expect } from "chai";
import { Contract } from "@ethersproject/contracts";
import { pit, RUNS } from "./library/property";
import { integer } from "fast-check";
import { OracleParamsStruct, RatioParamsStruct } from "./types/MStrategy";
import Exceptions from "./library/Exceptions";
import { assert } from "console";
import { randomInt } from "crypto";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    params: any;
    deployerWethAmount: BigNumber;
    deployerUsdcAmount: BigNumber;
};

type DeployOptions = {};

contract<MStrategy, DeployOptions, CustomContext>(
    "Integration__mstrategy",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

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
                    const erc20RootVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft + 1
                    );
                    this.erc20RootVault = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );
                    this.erc20Vault = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    );
                    this.yearnVault = await ethers.getContractAt(
                        "YearnVault",
                        yearnVault
                    );

                    /*
                     * Deploy MStrategy
                     */
                    const { uniswapV3PositionManager, uniswapV3Router } =
                        await getNamedAccounts();
                    const mStrategy = await (
                        await ethers.getContractFactory("MStrategy")
                    ).deploy(uniswapV3PositionManager, uniswapV3Router);
                    this.params = {
                        tokens: tokens,
                        erc20Vault: erc20Vault,
                        moneyVault: yearnVault,
                        fee: 3000,
                        admin: this.mStrategyAdmin.address,
                    };

                    const address = await mStrategy.callStatic.createStrategy(
                        this.params.tokens,
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        this.params.fee,
                        this.params.admin
                    );
                    await mStrategy.createStrategy(
                        this.params.tokens,
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        this.params.fee,
                        this.params.admin
                    );
                    this.subject = await ethers.getContractAt(
                        "MStrategy",
                        address
                    );

                    /*
                     * Configure oracles for the MStrategy
                     */
                    const oracleParams: OracleParamsStruct = {
                        oracleObservationDelta: 15,
                        maxTickDeviation: 50,
                        maxSlippageD: Math.round(0.1 * 10 ** 9),
                    };
                    const ratioParams: RatioParamsStruct = {
                        tickMin: 198240 - 5000,
                        tickMax: 198240 + 5000,
                        erc20MoneyRatioD: Math.round(0.1 * 10 ** 9),
                        minErc20MoneyRatioDeviationD: Math.round(
                            0.01 * 10 ** 9
                        ),
                        minTickRebalanceThreshold: 180,
                        tickNeighborhood: 60,
                        tickIncrease: 180,
                    };
                    let txs = [];
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "setOracleParams",
                            [oracleParams]
                        )
                    );
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "setRatioParams",
                            [ratioParams]
                        )
                    );
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .functions["multicall"](txs);

                    await combineVaults(
                        hre,
                        erc20VaultNft + 1,
                        [erc20VaultNft, yearnVaultNft],
                        this.subject.address,
                        this.deployer.address
                    );

                    /*
                     * Allow deployer to make deposits
                     */
                    await this.erc20RootVault
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    /*
                     * Mint USDC and WETH to deployer
                     */

                    this.deployerUsdcAmount = BigNumber.from(10)
                        .pow(6)
                        .mul(3000);
                    this.deployerWethAmount = BigNumber.from(10).pow(18);

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

                    /*
                     * Approve USDC and WETH to ERC20RootVault
                     */
                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        type DeployMockParams = {
            slot0Params?: {
                sqrtPriceX96?: BigNumber;
                tick?: Number;
                observationIndex?: Number;
                observationCardinality?: Number;
                observationCardinalityNext?: Number;
                feeProtocol?: Number;
                unlocked?: Boolean;
            };
            observationsParams?: {
                blockTimestamp?: Number;
                tickCumulative?: Number;
                secondsPerLiquidityCumulativeX128?: BigNumber;
                initialized?: Boolean;
                blockTimestampLast?: Number;
                tickCumulativeLast?: Number;
            };
        };
        async function deployMockContracts(params?: DeployMockParams) {
            let mockUniswapV3PoolFactory = await ethers.getContractFactory(
                "MockUniswapV3Pool"
            );
            let mockUniswapV3Pool = await mockUniswapV3PoolFactory.deploy();

            let mockUniswapV3FactoryFactory = await ethers.getContractFactory(
                "MockUniswapV3Factory"
            );
            let mockUniswapV3Factory = await mockUniswapV3FactoryFactory.deploy(
                mockUniswapV3Pool.address
            );

            let mockNonfungiblePositionManagerFcatory =
                await ethers.getContractFactory(
                    "MockNonfungiblePositionManager"
                );
            let mockNonfungiblePositionManager =
                await mockNonfungiblePositionManagerFcatory.deploy(
                    mockUniswapV3Factory.address
                );

            const { uniswapV3Router } = await getNamedAccounts();
            const mStrategy = await (
                await ethers.getContractFactory("MStrategy")
            ).deploy(mockNonfungiblePositionManager.address, uniswapV3Router);

            await mockUniswapV3Pool.setSlot0Params(
                params?.slot0Params?.sqrtPriceX96 ?? 0,
                params?.slot0Params?.tick ?? 0,
                params?.slot0Params?.observationIndex ?? 0,
                params?.slot0Params?.observationCardinality ?? 0,
                params?.slot0Params?.observationCardinalityNext ?? 0,
                params?.slot0Params?.feeProtocol ?? 0,
                params?.slot0Params?.unlocked ?? true
            );

            await mockUniswapV3Pool.setObservationsParams(
                params?.observationsParams?.blockTimestamp ?? 0,
                params?.observationsParams?.tickCumulative ?? 0,
                params?.observationsParams?.secondsPerLiquidityCumulativeX128 ??
                    0,
                params?.observationsParams?.initialized ?? false,
                params?.observationsParams?.blockTimestampLast ?? 0,
                params?.observationsParams?.tickCumulativeLast ?? 0
            );

            return mStrategy;
        }

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(this.subject.address).to.not.eq(
                    ethers.constants.AddressZero
                );
            });

            describe("edge cases", () => {
                describe("when positionManager_ address is zero", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        const { uniswapV3Router } = await getNamedAccounts();
                        let factory = await ethers.getContractFactory(
                            "MStrategy"
                        );
                        await expect(
                            factory.deploy(
                                ethers.constants.AddressZero,
                                uniswapV3Router
                            )
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });

                describe("when router_ address is zero", () => {
                    it("passes", async () => {
                        const { uniswapV3PositionManager } =
                            await getNamedAccounts();

                        let factory = await ethers.getContractFactory(
                            "MStrategy"
                        );
                        await expect(
                            factory.deploy(
                                uniswapV3PositionManager,
                                ethers.constants.AddressZero
                            )
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });

        describe("#createStrategy", () => {
            it("creates a new strategy and initializes it", async () => {
                const address = await this.subject
                    .connect(this.mStrategyAdmin)
                    .callStatic.createStrategy(
                        this.params.tokens,
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        this.params.fee,
                        this.params.admin
                    );

                expect(address).to.not.eq(ethers.constants.AddressZero);

                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .createStrategy(
                            this.params.tokens,
                            this.params.erc20Vault,
                            this.params.moneyVault,
                            this.params.fee,
                            this.params.admin
                        )
                ).to.not.be.reverted;
            });

            describe("access control", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .createStrategy(
                                    this.params.tokens,
                                    this.params.erc20Vault,
                                    this.params.moneyVault,
                                    this.params.fee,
                                    this.params.admin
                                )
                        ).to.not.be.reverted;
                    });
                });
            });

            describe("edge cases", () => {
                describe("when tokens.length is not equal 2", () => {
                    it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                        const tokensTooLong = [
                            this.weth.address,
                            this.usdc.address,
                            this.wbtc.address,
                        ]
                            .map((t) => t.toLowerCase())
                            .sort();
                        await expect(
                            this.subject.createStrategy(
                                tokensTooLong,
                                this.params.erc20Vault,
                                this.params.moneyVault,
                                this.params.fee,
                                this.params.admin
                            )
                        ).to.be.revertedWith(Exceptions.INVALID_LENGTH);

                        const tokensTooShort = [this.weth.address]
                            .map((t) => t.toLowerCase())
                            .sort();
                        await expect(
                            this.subject.createStrategy(
                                tokensTooShort,
                                this.params.erc20Vault,
                                this.params.moneyVault,
                                this.params.fee,
                                this.params.admin
                            )
                        ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                    });
                });

                describe("when erc20Vault vaultTokens do not match tokens_", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        const erc20VaultTokens = [
                            this.wbtc.address,
                            this.usdc.address,
                        ]
                            .map((t) => t.toLowerCase())
                            .sort();

                        let erc20VaultOwner = randomAddress();
                        const { vault: newERC20VaultAddress } =
                            await this.erc20VaultGovernance.callStatic.createVault(
                                erc20VaultTokens,
                                erc20VaultOwner
                            );
                        await this.erc20VaultGovernance.createVault(
                            erc20VaultTokens,
                            erc20VaultOwner
                        );
                        assert(
                            newERC20VaultAddress !==
                                ethers.constants.AddressZero
                        );

                        await expect(
                            this.subject.createStrategy(
                                this.params.tokens,
                                newERC20VaultAddress,
                                this.params.moneyVault,
                                this.params.fee,
                                this.params.admin
                            )
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });

                describe("when moneyVault vaultTokens do not match tokens_", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        const moneyVaultTokens = [
                            this.weth.address,
                            this.wbtc.address,
                        ]
                            .map((t) => t.toLowerCase())
                            .sort();

                        let moneyVaultOwner = randomAddress();
                        const { vault: newMoneyVaultAddress } =
                            await this.yearnVaultGovernance.callStatic.createVault(
                                moneyVaultTokens,
                                moneyVaultOwner
                            );
                        await this.yearnVaultGovernance.createVault(
                            moneyVaultTokens,
                            moneyVaultOwner
                        );
                        assert(
                            newMoneyVaultAddress !==
                                ethers.constants.AddressZero
                        );

                        await expect(
                            this.subject.createStrategy(
                                this.params.tokens,
                                this.params.erc20Vault,
                                newMoneyVaultAddress,
                                this.params.fee,
                                this.params.admin
                            )
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });

                describe("when UniSwapV3 pool for tokens does not exist", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        let erc20Factory = await ethers.getContractFactory(
                            "ERC20Token"
                        );
                        let erc20TokenOne = await erc20Factory.deploy();
                        let erc20TokenTwo = await erc20Factory.deploy();
                        assert(
                            erc20TokenOne.address !==
                                ethers.constants.AddressZero
                        );
                        assert(
                            erc20TokenTwo.address !==
                                ethers.constants.AddressZero
                        );

                        const tokens = [
                            erc20TokenOne.address,
                            erc20TokenTwo.address,
                        ]
                            .map((t) => t.toLowerCase())
                            .sort();

                        for (let i = 0; i < tokens.length; ++i) {
                            await this.protocolGovernance
                                .connect(this.admin)
                                .stagePermissionGrants(tokens[i], [
                                    PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                                ]);
                        }

                        await sleep(this.governanceDelay);

                        for (let i = 0; i < tokens.length; ++i) {
                            await this.protocolGovernance
                                .connect(this.admin)
                                .commitPermissionGrants(tokens[i]);
                        }

                        let erc20VaultOwner = randomAddress();
                        const { vault: newERC20VaultAddress } =
                            await this.erc20VaultGovernance.callStatic.createVault(
                                tokens,
                                erc20VaultOwner
                            );
                        await this.erc20VaultGovernance.createVault(
                            tokens,
                            erc20VaultOwner
                        );
                        assert(
                            newERC20VaultAddress !==
                                ethers.constants.AddressZero
                        );

                        let moneyVaultOwner = randomAddress();
                        const { vault: newMoneyVaultAddress } =
                            await this.erc20VaultGovernance.callStatic.createVault(
                                tokens,
                                moneyVaultOwner
                            );
                        await this.erc20VaultGovernance.createVault(
                            tokens,
                            moneyVaultOwner
                        );
                        assert(
                            newMoneyVaultAddress !==
                                ethers.constants.AddressZero
                        );

                        await expect(
                            this.subject.createStrategy(
                                tokens,
                                newERC20VaultAddress,
                                newMoneyVaultAddress,
                                this.params.fee,
                                this.params.admin
                            )
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });

        describe("#setOracleParams", () => {
            const oracleParams: OracleParamsStruct = {
                oracleObservationDelta: 10,
                maxTickDeviation: 100,
                maxSlippageD: BigNumber.from(Math.round(0.05 * 10 ** 9)),
            };

            it("sets new params for oracle", async () => {
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .setOracleParams(oracleParams);
                expect(
                    toObject(await this.subject.oracleParams())
                ).to.be.equivalent(oracleParams);
            });

            describe("access control", () => {
                it("allowed: MStrategy admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.mStrategyAdmin)
                            .setOracleParams(oracleParams)
                    ).to.not.be.reverted;
                });

                it("denied: any other address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .setOracleParams(oracleParams)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#setRatioParams", () => {
            const ratioParams: RatioParamsStruct = {
                tickMin: 198240 - 5000,
                tickMax: 198240 + 5000,
                erc20MoneyRatioD: BigNumber.from(Math.round(0.1 * 10 ** 9)),
                minErc20MoneyRatioDeviationD: BigNumber.from(
                    Math.round(0.01 * 10 ** 9)
                ),
                minTickRebalanceThreshold: 180,
                tickNeighborhood: 60,
                tickIncrease: 180,
            };

            it("sets new ratio params", async () => {
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .setRatioParams(ratioParams);
                expect(await this.subject.ratioParams()).to.be.equivalent(
                    ratioParams
                );
            });

            describe("access control", () => {
                it("allowed: MStrategy admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.mStrategyAdmin)
                            .setRatioParams(ratioParams)
                    ).to.not.be.reverted;
                });

                it("denied: any other address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject.connect(s).setRatioParams(ratioParams)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#manualPull", () => {
            it("pulls token amounts from fromVault to toVault", async () => {
                let amountWETH = randomInt(10 ** 4, 10 ** 6);
                let amountUSDC = randomInt(10 ** 4, 10 ** 6);

                await this.usdc
                    .connect(this.deployer)
                    .transfer(this.erc20Vault.address, amountUSDC);
                await this.weth
                    .connect(this.deployer)
                    .transfer(this.erc20Vault.address, amountWETH);

                assert(
                    Number(
                        await this.usdc.balanceOf(this.params.erc20Vault)
                    ) === amountUSDC
                );
                assert(
                    Number(
                        await this.weth.balanceOf(this.params.erc20Vault)
                    ) === amountWETH
                );

                let yTokensAddresses = await this.yearnVault.yTokens();
                let yTokens: IYearnProtocolVault[] = [];
                let yTokenBalances = [];
                for (let i = 0; i < yTokensAddresses.length; ++i) {
                    yTokens.push(
                        await ethers.getContractAt(
                            "IYearnProtocolVault",
                            yTokensAddresses[i]
                        )
                    );
                    yTokenBalances.push(
                        await yTokens[i].balanceOf(this.params.moneyVault)
                    );
                }

                for (let i = 0; i < yTokenBalances.length; ++i) {
                    expect(yTokenBalances[i]).to.be.eq(0);
                }

                let amountWETHtoPull = randomInt(0, amountWETH);
                let amountUSDCtoPull = randomInt(0, amountUSDC);

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .manualPull(
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        [amountUSDCtoPull, amountWETHtoPull],
                        []
                    );

                for (let i = 0; i < yTokens.length; ++i) {
                    yTokenBalances[i] = await yTokens[i].balanceOf(
                        this.params.moneyVault
                    );
                }

                for (let i = 0; i < yTokenBalances.length; ++i) {
                    expect(yTokenBalances[i]).to.be.gt(0);
                }

                expect(
                    await this.weth.balanceOf(this.params.erc20Vault)
                ).to.be.equal(BigNumber.from(amountWETH - amountWETHtoPull));
                expect(
                    await this.usdc.balanceOf(this.params.erc20Vault)
                ).to.be.equal(BigNumber.from(amountUSDC - amountUSDCtoPull));

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .manualPull(
                        this.params.moneyVault,
                        this.params.erc20Vault,
                        [amountUSDCtoPull, amountWETHtoPull],
                        []
                    );

                for (let i = 0; i < yTokens.length; ++i) {
                    yTokenBalances[i] = await yTokens[i].balanceOf(
                        this.params.moneyVault
                    );
                }

                for (let i = 0; i < yTokenBalances.length; ++i) {
                    expect(yTokenBalances[i]).to.be.eq(0);
                }

                let usdcBalanceAbsDif = (
                    await this.usdc.balanceOf(this.params.erc20Vault)
                )
                    .sub(amountUSDC)
                    .abs();
                let wethBalanceAbsDif = (
                    await this.weth.balanceOf(this.params.erc20Vault)
                )
                    .sub(amountWETH)
                    .abs();

                expect(
                    usdcBalanceAbsDif
                        .mul(10000)
                        .sub(BigNumber.from(amountUSDC))
                        .lte(0)
                ).to.be.true;
                expect(
                    wethBalanceAbsDif
                        .mul(10000)
                        .sub(BigNumber.from(amountWETH))
                        .lte(0)
                ).to.be.true;
            });

            describe("access control", () => {
                it("allowed: MStrategy admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.mStrategyAdmin)
                            .manualPull(
                                this.params.erc20Vault,
                                this.params.moneyVault,
                                [1, 1],
                                []
                            )
                    ).to.not.be.reverted;
                });

                it("denied: any other address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .manualPull(
                                    this.params.erc20Vault,
                                    this.params.moneyVault,
                                    [1, 1],
                                    []
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });

            describe("edge cases", () => {
                describe("when token pull amounts are 0", () => {
                    it("passes", async () => {
                        await expect(
                            this.subject
                                .connect(this.mStrategyAdmin)
                                .manualPull(
                                    this.params.erc20Vault,
                                    this.params.moneyVault,
                                    [0, 0],
                                    []
                                )
                        ).to.not.be.reverted;
                    });
                });
            });
        });

        describe("#rebalance", () => {
            it("performs a rebalance according to target ratios", async () => {
                await this.erc20RootVault
                    .connect(this.mStrategyAdmin)
                    .deposit(
                        [BigNumber.from(10 ** 5), BigNumber.from(10 ** 5)],
                        [0, 0],
                        []
                    );

                console.log(
                    (
                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .callStatic.rebalance()
                    ).toString()
                );
            });

            describe("access control", () => {
                it("allowed: MStrategy admin", async () => {
                    await expect(
                        this.subject.connect(this.mStrategyAdmin).rebalance()
                    ).to.not.be.reverted;
                });

                it("denied: any other address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject.connect(s).rebalance()
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#getAverageTick", () => {
            it("returns average UniswapV3Pool price tick", async () => {
                let params: DeployMockParams = {
                    slot0Params: {
                        tick: 198240,
                        observationIndex: 10,
                        observationCardinality: 100,
                        observationCardinalityNext: 110,
                        feeProtocol: 10,
                        unlocked: false,
                    },
                    observationsParams: {
                        blockTimestamp: 10 ** 8 + 100,
                        blockTimestampLast: 10 ** 8,
                        tickCumulative: 199240,
                        tickCumulativeLast: 198240,
                    },
                };
                let mStrategy: Contract = await deployMockContracts(params);
                const address = await mStrategy.callStatic.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.fee,
                    this.params.admin
                );
                await mStrategy.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.fee,
                    this.params.admin
                );
                this.subject = await ethers.getContractAt("MStrategy", address);

                const oracleParams: OracleParamsStruct = {
                    oracleObservationDelta: 10,
                    maxTickDeviation: 50,
                    maxSlippageD: Math.round(0.1 * 10 ** 9),
                };
                const ratioParams: RatioParamsStruct = {
                    tickMin: 198240 - 5000,
                    tickMax: 198240 + 5000,
                    erc20MoneyRatioD: Math.round(0.1 * 10 ** 9),
                    minErc20MoneyRatioDeviationD: Math.round(0.01 * 10 ** 9),
                    minTickRebalanceThreshold: 180,
                    tickNeighborhood: 60,
                    tickIncrease: 180,
                };

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .setRatioParams(ratioParams);
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .setOracleParams(oracleParams);

                let res = await this.subject.callStatic.getAverageTick();
                expect(res.averageTick).to.be.eq(params.observationsParams.tickCumulative - params.observationsParams.tickCumulativeLast)
                await expect(this.subject.getAverageTick()).to.not.be.reverted;
            });

            describe("edge cases", () => {
                describe("when observationCardinality <= oracleObservationDelta", () => {
                    it(`reverts with ${Exceptions.LIMIT_UNDERFLOW}`, async () => {
                        let params: DeployMockParams = {
                            slot0Params: {
                                tick: 198240,
                                observationIndex: 10,
                                observationCardinality: 100,
                            },
                        };
                        let mStrategy: Contract = await deployMockContracts(
                            params
                        );
                        const address =
                            await mStrategy.callStatic.createStrategy(
                                this.params.tokens,
                                this.params.erc20Vault,
                                this.params.moneyVault,
                                this.params.fee,
                                this.params.admin
                            );
                        await mStrategy.createStrategy(
                            this.params.tokens,
                            this.params.erc20Vault,
                            this.params.moneyVault,
                            this.params.fee,
                            this.params.admin
                        );
                        this.subject = await ethers.getContractAt(
                            "MStrategy",
                            address
                        );

                        const oracleParams: OracleParamsStruct = {
                            oracleObservationDelta: 101,
                            maxTickDeviation: 50,
                            maxSlippageD: Math.round(0.1 * 10 ** 9),
                        };
                        const ratioParams: RatioParamsStruct = {
                            tickMin: 198240 - 5000,
                            tickMax: 198240 + 5000,
                            erc20MoneyRatioD: Math.round(0.1 * 10 ** 9),
                            minErc20MoneyRatioDeviationD: Math.round(
                                0.01 * 10 ** 9
                            ),
                            minTickRebalanceThreshold: 180,
                            tickNeighborhood: 60,
                            tickIncrease: 180,
                        };

                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .setRatioParams(ratioParams);
                        await this.subject
                            .connect(this.mStrategyAdmin)
                            .setOracleParams(oracleParams);

                        await expect(
                            this.subject
                                .connect(this.mStrategyAdmin)
                                .rebalance()
                        ).to.be.revertedWith(Exceptions.LIMIT_UNDERFLOW);
                    });
                });
            });
        });
    }
);
