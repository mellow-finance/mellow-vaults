import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    withSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    ProtocolGovernance,
    UniV3Helper,
    UniV3Vault,
    ISwapRouter as SwapRouterInterface,
    HStrategyHelper,
} from "../types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    setupVault,
    combineVaults,
    TRANSACTION_GAS_LIMITS,
} from "../../deploy/0000_utils";
import { Contract } from "@ethersproject/contracts";
import { expect } from "chai";

import { MockHStrategy, StrategyParamsStruct } from "../types/MockHStrategy";
import {
    RatioParamsStruct,
    RebalanceRestrictionsStruct,
} from "../types/HStrategy";
import { DomainPositionParamsStruct } from "../types/HStrategyHelper";
import { TickMath } from "@uniswap/v3-sdk";

const Q96 = BigNumber.from(2).pow(96);

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
    swapRouter: SwapRouterInterface;
    hStrategyHelper: HStrategyHelper;
    strategyParams: StrategyParamsStruct;
};

type DeployOptions = {};

contract<MockHStrategy, DeployOptions, CustomContext>("HStrategy", function () {
    before(async () => {
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

                    const { address: uniV3Helper } = await ethers.getContract(
                        "UniV3Helper"
                    );

                    await deploy("HStrategyHelper", {
                        from: this.deployer.address,
                        contract: "HStrategyHelper",
                        args: [],
                        log: true,
                        autoMine: true,
                        ...TRANSACTION_GAS_LIMITS,
                    });
                    const { address: hStrategyHelper } =
                        await ethers.getContract("HStrategyHelper");

                    this.hStrategyHelper = await ethers.getContractAt(
                        "HStrategyHelper",
                        hStrategyHelper
                    );

                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                3000,
                                uniV3Helper,
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
                        hStrategyHelper: hStrategyHelper,
                    };

                    const address = await hStrategy.callStatic.createStrategy(
                        this.params.tokens,
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        this.params.uniV3Vault,
                        this.params.fee,
                        this.params.admin,
                        this.params.uniV3Helper,
                        this.params.hStrategyHelper
                    );
                    await hStrategy.createStrategy(
                        this.params.tokens,
                        this.params.erc20Vault,
                        this.params.moneyVault,
                        this.params.uniV3Vault,
                        this.params.fee,
                        this.params.admin,
                        this.params.uniV3Helper,
                        this.params.hStrategyHelper
                    );
                    this.subject = await ethers.getContractAt(
                        "MockHStrategy",
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

                    const strategyParams = {
                        widthCoefficient: 15,
                        widthTicks: 60,
                        globalLowerTick: 23400,
                        globalUpperTick: 29700,
                        tickNeighborhood: 0,
                        simulateUniV3Interval: false, // simulating uniV2 Interval
                    };
                    this.strategyParams = strategyParams;

                    const oracleParams = {
                        oracleObservationDelta: 150,
                        maxTickDeviation: 100,
                    };
                    this.oracleParams = oracleParams;

                    const ratioParams = {
                        erc20MoneyRatioD: BigNumber.from(10).pow(7).mul(5), // 5%
                        minUniV3RatioDeviation0D: BigNumber.from(10)
                            .pow(7)
                            .mul(5),
                        minUniV3RatioDeviation1D: BigNumber.from(10)
                            .pow(7)
                            .mul(5),
                        minMoneyRatioDeviation0D: BigNumber.from(10)
                            .pow(7)
                            .mul(5),
                        minMoneyRatioDeviation1D: BigNumber.from(10)
                            .pow(7)
                            .mul(5),
                    };
                    this.ratioParams = ratioParams;

                    const mintingParams = {
                        minToken0ForOpening: BigNumber.from(10).pow(6),
                        minToken1ForOpening: BigNumber.from(10).pow(6),
                    };
                    this.mintingParams = mintingParams;

                    let txs: string[] = [];
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "updateStrategyParams",
                            [strategyParams]
                        )
                    );
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "updateOracleParams",
                            [oracleParams]
                        )
                    );
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "updateRatioParams",
                            [ratioParams]
                        )
                    );
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "updateMintingParams",
                            [mintingParams]
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
                        await withSigner(
                            this.subject.address,
                            async (signer) => {
                                await this.positionManager
                                    .connect(signer)
                                    .functions[
                                        "safeTransferFrom(address,address,uint256)"
                                    ](
                                        signer.address,
                                        this.uniV3Vault.address,
                                        tokenId
                                    );
                            }
                        );
                    };

                    this.getPositionParams = async () => {
                        const strategyParams =
                            await this.subject.strategyParams();
                        const oracleParams = await this.subject.oracleParams();
                        const pool = await this.subject.pool();
                        const priceInfo =
                            await this.uniV3Helper.getAverageTickAndSqrtSpotPrice(
                                pool,
                                oracleParams.oracleObservationDelta
                            );
                        return await this.hStrategyHelper.calculateDomainPositionParams(
                            priceInfo.averageTick,
                            priceInfo.sqrtSpotPriceX96,
                            strategyParams,
                            await this.uniV3Vault.uniV3Nft(),
                            this.positionManager.address
                        );
                    };

                    this.getSqrtRatioAtTick = (tick: number) => {
                        return BigNumber.from(
                            TickMath.getSqrtRatioAtTick(tick).toString()
                        );
                    };

                    this.tvlToken0 = async () => {
                        const positionParams: DomainPositionParamsStruct =
                            await this.getPositionParams();
                        const averagePriceSqrtX96 = BigNumber.from(
                            positionParams.averagePriceSqrtX96
                        );
                        const price = averagePriceSqrtX96
                            .mul(averagePriceSqrtX96)
                            .div(Q96);
                        const currentAmounts =
                            await this.hStrategyHelper.calculateCurrentTokenAmounts(
                                this.erc20Vault.address,
                                this.yearnVault.address,
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
                    fee: 3000,
                    recipient: this.deployer.address,
                    deadline: ethers.constants.MaxUint256,
                    amountIn: delta.div(n),
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0,
                });
            }
        };

        describe.only("#rebalance", () => {
            it("performs a rebalance according to strategy params", async () => {
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .updateStrategyParams({
                        ...this.strategyParams,
                        widthCoefficient: 1,
                        widthTicks: 60,
                        globalLowerTick: -870000,
                        globalUpperTick: 870000,
                        simulateUniV3Interval: true,
                    } as StrategyParamsStruct);
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
                    [BigNumber.from(10).pow(14), BigNumber.from(10).pow(14)],
                    0,
                    []
                );

                var restrictions = {
                    pulledOnUniV3Vault: [0, 0],
                    pulledOnMoneyVault: [0, 0],
                    pulledFromUniV3Vault: [0, 0],
                    pulledFromMoneyVault: [0, 0],
                    swappedAmounts: [0, 0],
                    burnedAmounts: [0, 0],
                    deadline: ethers.constants.MaxUint256,
                } as RebalanceRestrictionsStruct;
                {
                    const ratioParams = await this.subject.ratioParams();
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .updateRatioParams({
                            ...ratioParams,
                            minUniV3RatioDeviation0D: 0,
                            minUniV3RatioDeviation1D: 0,
                            minMoneyRatioDeviation0D: 0,
                            minMoneyRatioDeviation1D: 0,
                        } as RatioParamsStruct);
                }

                const getAverageTick = async () => {
                    return (
                        await this.uniV3Helper.getAverageTickAndSqrtSpotPrice(
                            await this.subject.pool(),
                            30 * 60
                        )
                    ).averageTick;
                };

                const tvlBefore = (await this.erc20RootVault.tvl())
                    .minTokenAmounts;
                for (var i = 0; i < 10; i++) {
                    console.log("Iteration:", i);
                    if (Math.random() < 0.5) {
                        const initialTick = await getAverageTick();
                        var currentTick = initialTick;
                        while (Math.abs(currentTick - initialTick) <= 60) {
                            await push(BigNumber.from(10).pow(14), "USDC");
                            currentTick = await getAverageTick();
                        }
                    } else {
                        const initialTick = await getAverageTick();
                        var currentTick = initialTick;
                        while (Math.abs(currentTick - initialTick) <= 60) {
                            await push(BigNumber.from(10).pow(20), "WETH");
                            currentTick = await getAverageTick();
                        }
                    }
                    await this.subject.rebalance(restrictions, []);
                }

                const tvlAfter = (await this.erc20RootVault.tvl())
                    .minTokenAmounts;

                const token0Delta = tvlBefore[0].sub(tvlAfter[0]).abs();
                const token1Delta = tvlBefore[1].sub(tvlAfter[1]).abs();

                expect(token0Delta.lt(tvlBefore[0].div(10000))).to.be.true;
                expect(token1Delta.lt(tvlBefore[1].div(10000))).to.be.true;
            });
        });
    });
});
