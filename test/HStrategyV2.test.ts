import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Vault,
    ISwapRouter as SwapRouterInterface,
    MockHStrategyV2,
} from "./types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    setupVault,
    combineVaults,
    TRANSACTION_GAS_LIMITS,
} from "../deploy/0000_utils";
import { Contract } from "@ethersproject/contracts";
import { expect } from "chai";
import { TickMath } from "@uniswap/v3-sdk";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    uniV3Vault: UniV3Vault;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    deployerWethAmount: BigNumber;
    deployerUsdcAmount: BigNumber;
    swapRouter: SwapRouterInterface;
    params: any;
};

type DeployOptions = {};

const DENOMINATOR = BigNumber.from(10).pow(9);
const Q96 = BigNumber.from(2).pow(96);

contract<MockHStrategyV2, DeployOptions, CustomContext>(
    "HStrategyV2",
    function () {
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
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let yearnVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    let uniV3VaultNft = startNft + 2;
                    let erc20RootVaultNft = startNft + 3;
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
                        uniV3VaultNft,
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
                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );
                    const hStrategy = await (
                        await ethers.getContractFactory("MockHStrategyV2")
                    ).deploy(uniswapV3PositionManager, uniswapV3Router);
                    this.params = {
                        tokens: tokens,
                        erc20Vault: erc20Vault,
                        moneyVault: yearnVault,
                        uniV3Vault: uniV3Vault,
                        admin: this.mStrategyAdmin.address,
                    };

                    const address = await hStrategy.callStatic.createStrategy(
                        this.params.tokens,
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        this.params.uniV3Vault,
                        this.params.admin
                    );
                    await hStrategy.createStrategy(
                        this.params.tokens,
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        this.params.uniV3Vault,
                        this.params.admin
                    );
                    this.subject = await ethers.getContractAt(
                        "MockHStrategyV2",
                        address
                    );

                    this.swapRouter = await ethers.getContractAt(
                        ISwapRouter,
                        uniswapV3Router
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

                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .updateStrategyParams(
                            1800,
                            190800,
                            219600,
                            500,
                            5000000
                        );

                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [erc20VaultNft, yearnVaultNft, uniV3VaultNft],
                        this.subject.address,
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

                    this.pool = await ethers.getContractAt(
                        "IUniswapV3Pool",
                        await this.uniV3Vault.pool()
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
            it("deploys a new contract", async () => {
                expect(this.subject.address).to.not.eq(
                    ethers.constants.AddressZero
                );
            });
        });

        describe("#caclulateCurrentTvl", () => {
            it("", async () => {
                const slot0 = await this.pool.slot0();
                await expect(
                    this.subject
                        .connect(this.mStrategyAdmin)
                        .caclulateCurrentTvl(slot0[0])
                ).to.not.be.reverted;
            });
        });

        describe("#rebalance", () => {
            it("", async () => {
                await this.subject.connect(this.mStrategyAdmin).rebalance();
                await this.subject.connect(this.mStrategyAdmin).rebalance();
                await this.subject.connect(this.mStrategyAdmin).rebalance();

                const { sqrtPriceX96 } = await this.pool.slot0();
                const sqrtC = sqrtPriceX96;
                const priceX96 = sqrtPriceX96
                    .pow(2)
                    .div(BigNumber.from(2).pow(96));

                const { erc20Tvl, moneyTvl, uniV3Tvl, totalTvl } =
                    await this.subject.callStatic.caclulateCurrentTvl(
                        sqrtPriceX96
                    );

                const capital0 = totalTvl[0].add(
                    totalTvl[1].mul(Q96).div(priceX96)
                );

                console.log(
                    "Short Lower tick:",
                    await this.subject.shortLowerTick()
                );
                console.log(
                    "Short Upper tick:",
                    await this.subject.shortUpperTick()
                );
                console.log(
                    "Domain Lower tick:",
                    await this.subject.domainLowerTick()
                );
                console.log(
                    "Domain Upper tick:",
                    await this.subject.domainUpperTick()
                );
                console.log("Spot tick:", (await this.pool.slot0())[1]);

                const sqrtA = this.getSqrtRatioAtTick(
                    await this.subject.shortLowerTick()
                );

                const sqrtB = this.getSqrtRatioAtTick(
                    await this.subject.shortUpperTick()
                );
                const sqrtA0 = this.getSqrtRatioAtTick(
                    await this.subject.domainLowerTick()
                );
                const sqrtB0 = this.getSqrtRatioAtTick(
                    await this.subject.domainUpperTick()
                );

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

                const expectedUniV3Capital = capital0
                    .mul(uniV3RatioD)
                    .div(DENOMINATOR);
                const expectedToken0Capital = capital0
                    .mul(token0RatioD)
                    .div(DENOMINATOR);
                const expectedToken1Capital = capital0
                    .mul(token1RatioD)
                    .div(DENOMINATOR);

                const currentUniV3Capital = uniV3Tvl[0].add(
                    uniV3Tvl[1].mul(Q96).div(priceX96)
                );

                expect(expectedUniV3Capital.sub(100).lte(currentUniV3Capital))
                    .to.be.true;
                expect(expectedUniV3Capital.add(100).gte(currentUniV3Capital))
                    .to.be.true;

                expect(
                    expectedToken0Capital
                        .sub(100)
                        .lte(erc20Tvl[0].add(moneyTvl[0]))
                ).to.be.true;
                expect(
                    expectedToken0Capital
                        .add(100)
                        .gte(erc20Tvl[0].add(moneyTvl[0]))
                ).to.be.true;

                expect(
                    expectedToken1Capital
                        .sub(100)
                        .lte(erc20Tvl[1].add(moneyTvl[1]))
                ).to.be.true;
                expect(
                    expectedToken1Capital
                        .add(100)
                        .gte(
                            erc20Tvl[1].add(moneyTvl[1]).mul(Q96).div(priceX96)
                        )
                ).to.be.true;

                const currentRatio0D = erc20Tvl[0]
                    .mul(DENOMINATOR)
                    .div(erc20Tvl[0].add(moneyTvl[0]));
                const currentRatio1D = erc20Tvl[1]
                    .mul(DENOMINATOR)
                    .div(erc20Tvl[1].add(moneyTvl[1]));

                const expectedRatioD = await this.subject.erc20CapitalD();
                expect(expectedRatioD.sub(100).lte(currentRatio0D)).to.be.true;
                expect(expectedRatioD.add(100).gte(currentRatio0D)).to.be.true;

                expect(expectedRatioD.sub(100).lte(currentRatio1D)).to.be.true;
                expect(expectedRatioD.add(100).gte(currentRatio1D)).to.be.true;
            });
        });
    }
);
