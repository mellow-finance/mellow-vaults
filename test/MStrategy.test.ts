import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, randomAddress, sleep, withSigner } from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    MStrategy,
    ProtocolGovernance,
} from "./types";
import { setupVault, combineVaults } from "./../deploy/0000_utils";
import { expect } from "chai";
import { Contract } from "@ethersproject/contracts";
import { pit, RUNS } from "./library/property";
import { integer } from "fast-check";
import { OracleParamsStruct, RatioParamsStruct } from "./types/MStrategy";
import Exceptions from "./library/Exceptions";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    params: any;
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
                    await mint(
                        "USDC",
                        this.deployer.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
                    await mint(
                        "WETH",
                        this.deployer.address,
                        BigNumber.from(10).pow(18)
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

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(this.subject.address).to.not.eq(
                    ethers.constants.AddressZero
                );
            });

            describe("edge cases", () => {
                describe("when positionManager_ address is zero", () => {
                    it("passes", async () => {
                        const { uniswapV3Router } = await getNamedAccounts();
                        const mStrategyNew = await (
                            await ethers.getContractFactory("MStrategy")
                        ).deploy(ethers.constants.AddressZero, uniswapV3Router);
                        expect(mStrategyNew.address).to.not.eq(
                            ethers.constants.AddressZero
                        );
                    });
                });

                describe("when router_ address is zero", () => {
                    it("passes", async () => {
                        const { uniswapV3PositionManager } =
                            await getNamedAccounts();
                        const mStrategyNew = await (
                            await ethers.getContractFactory("MStrategy")
                        ).deploy(
                            uniswapV3PositionManager,
                            ethers.constants.AddressZero
                        );
                        expect(mStrategyNew.address).to.not.eq(
                            ethers.constants.AddressZero
                        );
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
                        const tokens = [
                            this.weth.address,
                            this.usdc.address,
                            this.wbtc.address,
                        ]
                            .map((t) => t.toLowerCase())
                            .sort();
                        await expect(
                            this.subject.createStrategy(
                                tokens,
                                this.params.erc20Vault,
                                this.params.moneyVault,
                                this.params.fee,
                                this.params.admin
                            )
                        ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                    });
                });
            });
        });
    }
);
