import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint } from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Vault,
    ISwapRouter as SwapRouterInterface,
    HStrategyV3,
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
import { MutableParamsStruct } from "./types/HStrategyV3";
import { IUniswapV3Pool } from "./types/IUniswapV3Pool";
import { HStrategyRebalancer } from "./types/HStrategyRebalancer";
import { fromAscii } from "ethjs-util";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    uniV3Vault500: UniV3Vault;
    uniV3Vault3000: UniV3Vault;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    deployerWethAmount: BigNumber;
    deployerUsdcAmount: BigNumber;
    swapRouter: SwapRouterInterface;
    params: any;
    pool: IUniswapV3Pool;
    rebalancer: HStrategyRebalancer;
};

type DeployOptions = {};

const DENOMINATOR = BigNumber.from(10).pow(9);
const Q96 = BigNumber.from(2).pow(96);

contract<HStrategyV3, DeployOptions, CustomContext>("HStrategyV3", function () {
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
                let uniV3Vault500Nft = startNft + 2;
                let uniV3Vault3000Nft = startNft + 3;
                let erc20RootVaultNft = startNft + 4;
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
                await setupVault(
                    hre,
                    uniV3Vault3000Nft,
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

                const uniV3Vault500 = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    uniV3Vault500Nft
                );

                const uniV3Vault3000 = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    uniV3Vault3000Nft
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );
                this.yearnVault = await ethers.getContractAt(
                    "YearnVault",
                    yearnVault
                );

                this.uniV3Vault500 = await ethers.getContractAt(
                    "UniV3Vault",
                    uniV3Vault500
                );

                this.uniV3Vault3000 = await ethers.getContractAt(
                    "UniV3Vault",
                    uniV3Vault3000
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

                this.swapRouter = await ethers.getContractAt(
                    ISwapRouter,
                    uniswapV3Router
                );

                const { address: rebalancerAddress } = await deploy(
                    "HStrategyRebalancer",
                    {
                        from: this.deployer.address,
                        contract: "HStrategyRebalancer",
                        args: [
                            this.deployer.address,
                            this.positionManager.address,
                        ],
                        log: true,
                        autoMine: true,
                        ...TRANSACTION_GAS_LIMITS,
                    }
                );

                this.pool = await ethers.getContractAt(
                    "IUniswapV3Pool",
                    await this.uniV3Vault500.pool()
                );

                const { address: hStrategyV3Address } = await deploy(
                    "HStrategyV3",
                    {
                        from: this.deployer.address,
                        contract: "HStrategyV3",
                        args: [
                            tokens[0],
                            tokens[1],
                            this.erc20Vault.address,
                            this.yearnVault.address,
                            this.pool.address,
                            this.swapRouter.address,
                            rebalancerAddress,
                            this.mStrategyAdmin.address,
                            Array.from([
                                this.uniV3Vault500.address,
                                this.uniV3Vault3000.address,
                            ]),
                        ],
                        log: true,
                        autoMine: true,
                        ...TRANSACTION_GAS_LIMITS,
                    }
                );

                this.subject = await ethers.getContractAt(
                    "HStrategyV3",
                    hStrategyV3Address
                );

                this.rebalancer = await ethers.getContractAt(
                    "HStrategyRebalancer",
                    await this.subject.rebalancer()
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
                    .updateMutableParams({
                        halfOfShortInterval: 1800,
                        domainLowerTick: 190800,
                        domainUpperTick: 219600,
                        amount0ForMint: 10 ** 9,
                        amount1ForMint: 10 ** 9,
                        erc20CapitalD: 5000000,
                        uniV3Weights: [1, 1],
                    } as MutableParamsStruct);

                await combineVaults(
                    hre,
                    erc20RootVaultNft,
                    [
                        erc20VaultNft,
                        yearnVaultNft,
                        uniV3Vault500Nft,
                        uniV3Vault3000Nft,
                    ],
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
                    this.rebalancer.address,
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

    describe("#constructor", () => {
        it("deploys a new contract", async () => {
            expect(this.subject.address).to.not.eq(
                ethers.constants.AddressZero
            );
        });
    });

    describe.only("#rebalance", () => {
        it("works correctly", async () => {
            await this.subject.connect(this.mStrategyAdmin).rebalance();
            await this.subject.connect(this.mStrategyAdmin).rebalance();
            await this.subject.connect(this.mStrategyAdmin).rebalance();
            await this.subject.connect(this.mStrategyAdmin).rebalance();
            await this.subject.connect(this.mStrategyAdmin).rebalance();
            // const { sqrtPriceX96 } = await this.pool.slot0();
            // const sqrtC = sqrtPriceX96;
            // const priceX96 = sqrtPriceX96.pow(2).div(BigNumber.from(2).pow(96));
            // const { erc20Tvl, moneyTvl, uniV3Tvl, totalTvl } =
            //     await this.subject.callStatic.caclulateCurrentTvl(sqrtPriceX96);
            // const capital0 = totalTvl[0].add(
            //     totalTvl[1].mul(Q96).div(priceX96)
            // );

            // const sqrtA = this.getSqrtRatioAtTick(
            //     await this.subject.shortLowerTick()
            // );
            // const sqrtB = this.getSqrtRatioAtTick(
            //     await this.subject.shortUpperTick()
            // );
            // const sqrtA0 = this.getSqrtRatioAtTick(
            //     await this.subject.domainLowerTick()
            // );
            // const sqrtB0 = this.getSqrtRatioAtTick(
            //     await this.subject.domainUpperTick()
            // );
            // const uniV3RatioD = DENOMINATOR.mul(
            //     Q96.mul(2)
            //         .sub(sqrtA.mul(Q96).div(sqrtC))
            //         .sub(sqrtC.mul(Q96).div(sqrtB))
            // ).div(
            //     Q96.mul(2)
            //         .sub(sqrtA0.mul(Q96).div(sqrtC))
            //         .sub(sqrtC.mul(Q96).div(sqrtB0))
            // );
            // const token0RatioD = DENOMINATOR.mul(
            //     Q96.mul(sqrtC).div(sqrtB).sub(Q96.mul(sqrtC).div(sqrtB0))
            // ).div(
            //     Q96.mul(2)
            //         .sub(sqrtA0.mul(Q96).div(sqrtC))
            //         .sub(sqrtC.mul(Q96).div(sqrtB0))
            // );
            // const token1RatioD = DENOMINATOR.mul(
            //     Q96.mul(sqrtA).div(sqrtC).sub(Q96.mul(sqrtA0).div(sqrtC))
            // ).div(
            //     Q96.mul(2)
            //         .sub(sqrtA0.mul(Q96).div(sqrtC))
            //         .sub(sqrtC.mul(Q96).div(sqrtB0))
            // );
            // expect(
            //     uniV3RatioD.add(token0RatioD).add(token1RatioD).toNumber()
            // ).to.be.closeTo(DENOMINATOR.toNumber(), 1000);
            // const expectedUniV3Capital = capital0
            //     .mul(uniV3RatioD)
            //     .div(DENOMINATOR);
            // const expectedToken0Capital = capital0
            //     .mul(token0RatioD)
            //     .div(DENOMINATOR);
            // const expectedToken1Capital = capital0
            //     .mul(token1RatioD)
            //     .div(DENOMINATOR);
            // const currentUniV3Capital = uniV3Tvl[0].add(
            //     uniV3Tvl[1].mul(Q96).div(priceX96)
            // );
            // expect(expectedUniV3Capital.sub(100).lte(currentUniV3Capital)).to.be
            //     .true;
            // expect(expectedUniV3Capital.add(100).gte(currentUniV3Capital)).to.be
            //     .true;
            // expect(
            //     expectedToken0Capital.sub(100).lte(erc20Tvl[0].add(moneyTvl[0]))
            // ).to.be.true;
            // expect(
            //     expectedToken0Capital.add(100).gte(erc20Tvl[0].add(moneyTvl[0]))
            // ).to.be.true;
            // expect(
            //     expectedToken1Capital.sub(100).lte(erc20Tvl[1].add(moneyTvl[1]))
            // ).to.be.true;
            // expect(
            //     expectedToken1Capital
            //         .add(100)
            //         .gte(erc20Tvl[1].add(moneyTvl[1]).mul(Q96).div(priceX96))
            // ).to.be.true;
            // const currentRatio0D = erc20Tvl[0]
            //     .mul(DENOMINATOR)
            //     .div(erc20Tvl[0].add(moneyTvl[0]));
            // const currentRatio1D = erc20Tvl[1]
            //     .mul(DENOMINATOR)
            //     .div(erc20Tvl[1].add(moneyTvl[1]));
            // const expectedRatioD = await this.subject.erc20CapitalD();
            // expect(expectedRatioD.sub(100).lte(currentRatio0D)).to.be.true;
            // expect(expectedRatioD.add(100).gte(currentRatio0D)).to.be.true;
            // expect(expectedRatioD.sub(100).lte(currentRatio1D)).to.be.true;
            // expect(expectedRatioD.add(100).gte(currentRatio1D)).to.be.true;
        });
    });
});
