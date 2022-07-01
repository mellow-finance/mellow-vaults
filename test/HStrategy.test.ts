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
    MockHStrategy,
    UniV3Helper,
    UniV3Vault,
    IYearnProtocolVault,
} from "./types";
import {
    setupVault,
    combineVaults,
    TRANSACTION_GAS_LIMITS,
} from "../deploy/0000_utils";
import { Contract } from "@ethersproject/contracts";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";
import { expect } from "chai";
import { randomInt } from "crypto";

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

                for (let addr of [
                    this.subject.address,
                    this.erc20RootVault.address,
                ]) {
                    await this.weth.approve(addr, ethers.constants.MaxUint256);
                    await this.usdc.approve(addr, ethers.constants.MaxUint256);
                }

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe.only("#constructor", () => {
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

    describe("#constructor", () => {
        it("deploys a new contract", async () => {
            expect(this.subject.address).to.not.eq(
                ethers.constants.AddressZero
            );
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

    ContractMetaBehaviour.call(this, {
        contractName: "HStrategy",
        contractVersion: "1.0.0",
    });
});
