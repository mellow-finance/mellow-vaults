import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    randomAddress,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Helper,
    UniV3Vault,
    IYearnProtocolVault,
} from "./types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import {
    setupVault,
    combineVaults,
    TRANSACTION_GAS_LIMITS,
} from "../deploy/0000_utils";
import { Contract } from "@ethersproject/contracts";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";
import { expect } from "chai";
import { randomInt } from "crypto";
import {
    MockHStrategy,
    DomainPositionParamsStruct,
    TokenAmountsStruct,
    StrategyParamsStruct,
} from "./types/MockHStrategy";
import { TickMath } from "@uniswap/v3-sdk";

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
};

type DeployOptions = {};

contract<MockHStrategy, DeployOptions, CustomContext>("HStrategy", function () {
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
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;
                let yearnVaultNft = startNft;
                let erc20VaultNft = startNft + 1;
                let uniV3VaultNft = startNft + 2;
                let erc20RootVaultNft = startNft + 3;
                await setupVault(hre, yearnVaultNft, "YearnVaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

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

                await setupVault(hre, uniV3VaultNft, "UniV3VaultGovernance", {
                    createVaultArgs: [
                        tokens,
                        this.deployer.address,
                        3000,
                        uniV3Helper,
                    ],
                });
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
                };

                const address = await hStrategy.callStatic.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.uniV3Vault,
                    this.params.fee,
                    this.params.admin,
                    this.params.uniV3Helper
                );
                await hStrategy.createStrategy(
                    this.params.tokens,
                    this.params.erc20Vault,
                    this.params.moneyVault,
                    this.params.uniV3Vault,
                    this.params.fee,
                    this.params.admin,
                    this.params.uniV3Helper
                );
                this.subject = await ethers.getContractAt(
                    "MockHStrategy",
                    address
                );

                /*
                 * Configure oracles for the HStrategy
                 */

                const startegyParams = {
                    widthCoefficient: 15,
                    widthTicks: 60,
                    oracleObservationDelta: 150,
                    erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5), // 5%
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
                    globalLowerTick: 23400,
                    globalUpperTick: 29700,
                    simulateUniV3Interval: false, // simulating uniV2 Interval
                };

                let txs: string[] = [];
                txs.push(
                    this.subject.interface.encodeFunctionData(
                        "updateStrategyParams",
                        [startegyParams]
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

                this.deployerUsdcAmount = BigNumber.from(10).pow(9).mul(3000);
                this.deployerWethAmount = BigNumber.from(10).pow(18).mul(4000);

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
                    await this.weth.approve(addr, ethers.constants.MaxUint256);
                    await this.usdc.approve(addr, ethers.constants.MaxUint256);
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
                    await withSigner(this.subject.address, async (signer) => {
                        await this.positionManager
                            .connect(signer)
                            .functions[
                                "safeTransferFrom(address,address,uint256)"
                            ](signer.address, this.uniV3Vault.address, tokenId);
                    });
                };

                this.getPositionParams = async () => {
                    const strategyParams = await this.subject.strategyParams();
                    const pool = await this.subject.pool();
                    const priceInfo =
                        await this.uniV3Helper.getAverageTickAndSqrtSpotPrice(
                            pool,
                            strategyParams.oracleObservationDelta
                        );
                    return await this.subject.calculateDomainPositionParams(
                        priceInfo.averageTick,
                        priceInfo.sqrtSpotPriceX96,
                        strategyParams,
                        await this.uniV3Vault.uniV3Nft(),
                        this.positionManager.address
                    );
                };

                this.tvlToken0 = async () => {
                    const Q96 = BigNumber.from(2).pow(96);
                    const positionParams: DomainPositionParamsStruct =
                        await this.getPositionParams();
                    const averagePriceSqrtX96 = BigNumber.from(
                        positionParams.averagePriceSqrtX96
                    );
                    const price = averagePriceSqrtX96
                        .mul(averagePriceSqrtX96)
                        .div(Q96);
                    const currentAmounts =
                        await this.subject.calculateCurrentTokenAmounts(
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

    // Andrey:
    describe("#constructor", () => {
        it("deploys a new contract", async () => {
            expect(this.subject.address).to.not.eq(
                ethers.constants.AddressZero
            );
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
                    this.params.uniV3Vault,
                    this.params.fee,
                    this.params.admin,
                    this.params.uniV3Helper
                );

            expect(address).to.not.eq(ethers.constants.AddressZero);

            await expect(
                this.subject
                    .connect(this.mStrategyAdmin)
                    .createStrategy(
                        this.params.tokens,
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        this.params.uniV3Vault,
                        this.params.fee,
                        this.params.admin,
                        this.params.uniV3Helper
                    )
            ).to.not.be.reverted;
        });
    });

    describe("updateStrategyParams", () => {});

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
    });

    describe("#rebalance", () => {
        it("performs a rebalance according to strategy params", async () => {
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
                [BigNumber.from(10).pow(11), BigNumber.from(10).pow(11)],
                0,
                []
            );

            // await this.subject
            //         .connect(this.mStrategyAdmin)
            //         .rebalance(
            //             [0, 0],
            //             [0, 0],
            //             [0, 0],
            //             [0, 0],
            //             [0, 0],
            //             [0, 0],
            //             ethers.constants.MaxUint256,
            //             []
            //         )
        });
    });

    const getDomainPositionParams = () => {
        return {
            nft: 0,
            liquidity: 0,
            lowerTick: 0,
            upperTick: 0,
            lower0Tick: 0,
            upper0Tick: 0,
            averageTick: 0,
            lowerPriceSqrtX96: 0,
            upperPriceSqrtX96: 0,
            lower0PriceSqrtX96: 0,
            upper0PriceSqrtX96: 0,
            averagePriceSqrtX96: 0,
            averagePriceX96: 0,
            spotPriceSqrtX96: 0,
        } as DomainPositionParamsStruct;
    };

    /* describe("calculateExpectedRatios", () => {
        it("", async () => {
            this.subject.calculateExpectedRatios(getDomainPositionParams());
        });
    }); */

    describe("calculateDomainPositionParams", () => {});

    describe("calculateExpectedTokenAmountsInToken0", () => {});

    describe("calculateCurrentTokenAmountsInToken0", () => {});

    // Artyom:
    describe("#calculateCurrentTokenAmounts", () => {
        beforeEach(async () => {
            await this.mintMockPosition();
        });
        describe("initial zero", () => {
            it("equals zero", async () => {
                const positionParams = await this.getPositionParams();
                const result = await this.subject.calculateCurrentTokenAmounts(
                    positionParams
                );
                expect(result.erc20Token0.toNumber()).to.be.eq(0);
                expect(result.erc20Token1.toNumber()).to.be.eq(0);
                expect(result.moneyToken0.toNumber()).to.be.eq(0);
                expect(result.moneyToken1.toNumber()).to.be.eq(0);
                expect(result.uniV3Token0.gt(0) || result.uniV3Token1.gt(0)).to
                    .be.true;
                const pullExistentials =
                    await this.uniV3Vault.pullExistentials();
                expect(result.uniV3Token0.lte(pullExistentials[0])).to.be.true;
                expect(result.uniV3Token1.lte(pullExistentials[1])).to.be.true;
            });
        });

        describe("erc20 vault", () => {
            it("works", async () => {
                const positionParams = await this.getPositionParams();
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6)
                );
                {
                    const { erc20Token0, erc20Token1 } =
                        await this.subject.calculateCurrentTokenAmounts(
                            positionParams
                        );
                    expect(
                        erc20Token0.sub(BigNumber.from(10).pow(6)).toNumber()
                    ).to.be.eq(0);
                    expect(
                        erc20Token1.sub(BigNumber.from(10).pow(18)).toNumber()
                    ).to.be.eq(0);
                }
                await withSigner(this.erc20Vault.address, async (signer) => {
                    await this.weth
                        .connect(signer)
                        .transfer(
                            randomAddress(),
                            BigNumber.from(10).pow(18).div(2)
                        );
                    await this.usdc
                        .connect(signer)
                        .transfer(
                            randomAddress(),
                            BigNumber.from(10).pow(6).div(2)
                        );
                });
                {
                    const { erc20Token0, erc20Token1 } =
                        await this.subject.calculateCurrentTokenAmounts(
                            positionParams
                        );
                    expect(
                        erc20Token0
                            .sub(BigNumber.from(10).pow(6).div(2))
                            .toNumber()
                    ).to.be.eq(0);
                    expect(
                        erc20Token1
                            .sub(BigNumber.from(10).pow(18).div(2))
                            .toNumber()
                    ).to.be.eq(0);
                }
            });
        });

        describe("money vault", () => {
            it("works", async () => {
                const positionParams = await this.getPositionParams();
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6)
                );
                await withSigner(this.subject.address, async (signer) => {
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.yearnVault.address,
                            [this.usdc.address, this.weth.address],
                            [
                                BigNumber.from(10).pow(6),
                                BigNumber.from(10).pow(18),
                            ],
                            []
                        );
                });
                // {
                //     const { moneyToken0, moneyToken1 } = await this.subject.calculateCurrentTokenAmounts(positionParams);
                //     expect(moneyToken0.sub(BigNumber.from(10).pow(6)).toNumber()).to.be.eq(0);
                //     expect(moneyToken1.sub(BigNumber.from(10).pow(18)).toNumber()).to.be.eq(0);
                // }
                await withSigner(this.subject.address, async (signer) => {
                    await this.yearnVault
                        .connect(signer)
                        .pull(
                            this.erc20Vault.address,
                            [this.usdc.address, this.weth.address],
                            [
                                ethers.constants.MaxUint256,
                                ethers.constants.MaxUint256,
                            ],
                            []
                        );
                });
                {
                    const { moneyToken0, moneyToken1 } =
                        await this.subject.calculateCurrentTokenAmounts(
                            positionParams
                        );
                    expect(moneyToken0.toNumber()).to.be.eq(0);
                    expect(moneyToken1.toNumber()).to.be.eq(0);
                }
            });
        });

        describe("uni v3 vault", () => {
            it("works", async () => {
                await this.weth.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18)
                );
                await this.usdc.transfer(
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(6).mul(2000)
                );
                await withSigner(this.subject.address, async (signer) => {
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.uniV3Vault.address,
                            [this.usdc.address, this.weth.address],
                            [
                                BigNumber.from(10).pow(6).mul(2000),
                                BigNumber.from(10).pow(18),
                            ],
                            []
                        );
                });

                // {
                //     const positionParams = await this.getPositionParams();
                //     const requiedAmounts = await this.uniV3Helper.liquidityToTokenAmounts(
                //         positionParams.liquidity,
                //         this.pool.address,
                //         await this.uniV3Vault.uniV3Nft(),
                //         this.positionManager.address,
                //     );
                //     const { uniV3Token0, uniV3Token1 } = await this.subject.calculateCurrentTokenAmounts(positionParams);
                //     expect(uniV3Token0.sub(requiedAmounts[0]).toNumber()).to.be.eq(0);
                //     expect(uniV3Token1.sub(requiedAmounts[1]).toNumber()).to.be.eq(0);
                // }

                await withSigner(this.subject.address, async (signer) => {
                    await this.uniV3Vault
                        .connect(signer)
                        .pull(
                            this.erc20Vault.address,
                            [this.usdc.address, this.weth.address],
                            [
                                BigNumber.from(2).pow(96),
                                BigNumber.from(2).pow(96),
                            ],
                            []
                        );
                });

                {
                    const positionParams = await this.getPositionParams();
                    const { uniV3Token0, uniV3Token1 } =
                        await this.subject.calculateCurrentTokenAmounts(
                            positionParams
                        );
                    expect(uniV3Token0.toNumber()).to.be.eq(0);
                    expect(uniV3Token1.toNumber()).to.be.eq(0);
                }
            });
        });
    });

    describe("calculateExpectedTokenAmounts", () => {
        beforeEach(async () => {
            await this.mintMockPosition();
        });

        const actualExpectedTokenAmounts = async (
            amountParams: TokenAmountsStruct,
            strategyParams: StrategyParamsStruct
        ) => {
            const positionParams = await this.getPositionParams();
            return await this.subject.calculateExpectedTokenAmounts(
                amountParams,
                strategyParams,
                positionParams
            );
        };

        const calculateRatiosUniV3 = async () => {
            const Q96 = BigNumber.from(2).pow(96);
            const positionParams: DomainPositionParamsStruct =
                await this.getPositionParams();
            const averagePriceSqrtX96 = BigNumber.from(
                positionParams.averagePriceSqrtX96
            );
            const price = averagePriceSqrtX96.mul(averagePriceSqrtX96).div(Q96);
            const denominator = averagePriceSqrtX96
                .mul(2)
                .sub(positionParams.lower0PriceSqrtX96)
                .sub(price.mul(Q96).div(positionParams.upper0PriceSqrtX96));
            const nominator0 = price
                .mul(Q96)
                .div(positionParams.upperPriceSqrtX96)
                .sub(price.mul(Q96).div(positionParams.upper0PriceSqrtX96));
            const nominator1 = BigNumber.from(
                positionParams.lowerPriceSqrtX96
            ).sub(positionParams.lower0PriceSqrtX96);
            const DENOMINATOR = BigNumber.from(10).pow(9);
            const ratio0 = nominator0.mul(DENOMINATOR).div(denominator);
            const ratio1 = nominator1.mul(DENOMINATOR).div(denominator);
            return { ratio0, ratio1 };
        };

        const getExpectedCapital = async (
            strategyParams: StrategyParamsStruct
        ) => {
            const DENOMINATOR = BigNumber.from(10).pow(9);
            const { ratio0, ratio1 } = await calculateRatiosUniV3();
            const tvl0 = await this.tvlToken0();
            const totalCapital = tvl0.erc20Vault
                .add(tvl0.moneyVault)
                .add(tvl0.uniV3Vault);
            const capitalUni = totalCapital.sub(
                DENOMINATOR.sub(ratio0).sub(ratio1)
            );
            const capitalERC20 = totalCapital
                .sub(capitalUni)
                .mul(strategyParams.erc20MoneyRatioD)
                .div(DENOMINATOR);
            const moneyCapital = totalCapital.sub(capitalUni).sub(capitalERC20);
            return { capitalUni, capitalERC20, moneyCapital };
        };

        const requiredExpectedTokenAmounts = async (
            strategyParams: StrategyParamsStruct
        ) => {
            const { capitalUni, capitalERC20, moneyCapital } =
                await getExpectedCapital(strategyParams);
            console.log("Expected capital: ", {
                capitalUni,
                capitalERC20,
                moneyCapital,
            });
            const { ratio0, ratio1 } = await calculateRatiosUniV3();
            const Q96 = BigNumber.from(2).pow(96);
            const positionParams: DomainPositionParamsStruct =
                await this.getPositionParams();
            const erc20Token0 = capitalERC20
                .mul(ratio0)
                .div(ratio0.add(ratio1));
            const erc20Token1 = capitalERC20
                .sub(erc20Token0)
                .mul(positionParams.averagePriceX96)
                .div(Q96);
            const moneyToken0 = moneyCapital
                .mul(ratio0)
                .div(ratio0.add(ratio1));
            const moneyToken1 = moneyCapital
                .sub(moneyToken0)
                .mul(positionParams.averagePriceX96)
                .div(Q96);
            const capitalUniRatio = BigNumber.from(
                positionParams.spotPriceSqrtX96
            )
                .sub(positionParams.lowerPriceSqrtX96)
                .div(
                    BigNumber.from(positionParams.upperPriceSqrtX96).sub(
                        positionParams.spotPriceSqrtX96
                    )
                )
                .mul(positionParams.upperPriceSqrtX96)
                .div(positionParams.spotPriceSqrtX96);
            const capitalUni1 = capitalUni
                .mul(capitalUniRatio)
                .div(capitalUniRatio.add(Q96));
            const uniV3Token0 = capitalUni.sub(capitalUni1);
            const priceX96 = BigNumber.from(positionParams.spotPriceSqrtX96)
                .mul(positionParams.spotPriceSqrtX96)
                .div(Q96);
            const uniV3Token1 = capitalUni1.mul(priceX96).div(Q96);
            return {
                erc20Token0,
                erc20Token1,
                moneyToken0,
                moneyToken1,
                uniV3Token0,
                uniV3Token1,
            } as TokenAmountsStruct;
        };

        describe("on initial position", () => {
            it("works", async () => {
                const strategyParams = await this.subject.strategyParams();
                const currentAmounts =
                    await this.subject.calculateCurrentTokenAmounts(
                        await this.getPositionParams()
                    );
                const required = await requiredExpectedTokenAmounts(
                    strategyParams
                );
                const actual = await actualExpectedTokenAmounts(
                    currentAmounts,
                    strategyParams
                );
                console.log("Required: ", required);
                console.log("Actual: ", actual);
            });
        });
    });

    describe("calculateExtraTokenAmountsForMoneyVault", () => {});

    describe("  ", () => {});

    describe("swapTokens", () => {});

    ContractMetaBehaviour.call(this, {
        contractName: "HStrategy",
        contractVersion: "1.0.0",
    });
});
