import { expect } from "chai";
import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";

import { contract } from "./library/setup";
import {
    ERC20Vault,
    SStrategy,
    MockCowswap,
    MockOracle,
    UniV3Vault,
    RequestableRootVault,
    SqueethVault,
} from "./types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { abi as ICurvePool } from "./helpers/curvePoolABI.json";
import { abi as IWETH } from "./helpers/wethABI.json";
import { abi as IWSTETH } from "./helpers/wstethABI.json";
import {
    encodeToBytes,
    generateSingleParams,
    mint,
    randomAddress,
    sleep,
    uniSwapTokensGivenInput,
    withSigner,
} from "./library/Helpers";
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
import { uint256 } from "./library/property";

type CustomContext = {
    erc20Vault: ERC20Vault;
    squeethVault: SqueethVault;
    rootVault: RequestableRootVault;
};

type DeployOptions = {};

contract<SStrategy, DeployOptions, CustomContext>("SStrategy", function () {
    const uniV3PoolFee = 500;
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const {
                    uniswapV3PositionManager,
                    uniswapV3Router,
                    mStrategyAdmin,
                } = await getNamedAccounts();

                let strategyTreasury = randomAddress();

                this.swapRouter = await ethers.getContractAt(
                    ISwapRouter,
                    uniswapV3Router
                );

                const tokens = [this.weth.address];

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let erc20VaultNft = startNft;
                let squeethVaultNft = startNft + 1;
                let rootVaultNft = startNft + 2;
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                await setupVault(
                    hre,
                    squeethVaultNft,
                    "SqueethVaultGovernance",
                    {
                        createVaultArgs: [this.deployer.address],
                    }
                );

                const { deploy } = deployments;

                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );
                const squeethVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    squeethVaultNft
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );

                this.squeethVault = await ethers.getContractAt(
                    "SqueethVault",
                    squeethVault
                );

                let strategyDeployParams = await deploy("SStrategy", {
                    from: this.deployer.address,
                    contract: "SStrategy",
                    args: [
                        this.weth.address,
                        this.erc20Vault.address,
                        this.squeethVault.address,
                        this.swapRouter.address,
                        this.deployer.address,
                    ],
                    log: true,
                    autoMine: true,
                });

                await combineVaults(
                    hre,
                    rootVaultNft,
                    [erc20VaultNft, squeethVaultNft],
                    strategyDeployParams.address,
                    strategyTreasury,
                    undefined,
                    "RequestableRootVault"
                );
                await withSigner(mStrategyAdmin, async (s) => {
                    await this.vaultRegistry
                        .connect(s)
                        .approve(strategyDeployParams.address, rootVaultNft);
                });

                const requestableRootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    rootVaultNft
                );

                this.rootVault = await ethers.getContractAt(
                    "RequestableRootVault",
                    requestableRootVault
                );

                //TODO: validator

                this.subject = await ethers.getContractAt(
                    "SStrategy",
                    strategyDeployParams.address
                );

                await this.subject.setRootVault(this.rootVault.address);

                await mint(
                    "WETH",
                    this.subject.address,
                    BigNumber.from(10).pow(18).mul(100)
                );
                await mint(
                    "WETH",
                    this.deployer.address,
                    BigNumber.from(10).pow(18).mul(100)
                );

                await this.subject.updateStrategyParams({
                    lowerHedgingThresholdD9: BigNumber.from(10).pow(8).mul(5),
                    upperHedgingThresholdD9: BigNumber.from(10).pow(9).mul(2),
                    cycleDuration: BigNumber.from(3600).mul(24).mul(28),
                });

                await this.subject.updateLiquidationParams({
                    lowerLiquidationThresholdD9: BigNumber.from(10)
                        .pow(8)
                        .mul(5),
                    upperLiquidationThresholdD9: BigNumber.from(10)
                        .pow(8)
                        .mul(18),
                });

                await this.subject.updateOracleParams({
                    maxTickDeviation: BigNumber.from(100),
                    slippageD9: BigNumber.from(10).pow(7),
                    oracleObservationDelta: BigNumber.from(15 * 60),
                });
                this.firstDepositor = randomAddress();
                this.firstDepositAmount = BigNumber.from(10).pow(12);
                await mint(
                    "WETH",
                    this.firstDepositor,
                    BigNumber.from(10).pow(18).mul(100)
                );
                await this.rootVault
                    .connect(this.admin)
                    .addDepositorsToAllowlist([this.firstDepositor]);

                await withSigner(this.firstDepositor, async (s) => {
                    await this.weth
                        .connect(s)
                        .approve(
                            this.rootVault.address,
                            this.firstDepositAmount
                        );
                    await this.rootVault
                        .connect(s)
                        .deposit([this.firstDepositAmount], 0, randomBytes(4));
                });

                this.depositor = randomAddress();
                this.depositAmount = generateSingleParams(uint256)
                    .mod(BigNumber.from(10).pow(18).mul(1))
                    .add(BigNumber.from(10).pow(18).mul(9));
                await mint(
                    "WETH",
                    this.depositor,
                    BigNumber.from(10).pow(18).mul(10)
                );
                await withSigner(this.depositor, async (s) => {
                    await this.weth
                        .connect(s)
                        .approve(this.rootVault.address, this.depositAmount);
                });

                await this.rootVault
                    .connect(this.admin)
                    .addDepositorsToAllowlist([this.depositor]);

                this.safe = randomAddress();
                await mint(
                    "WETH",
                    this.safe,
                    BigNumber.from(10).pow(18).mul(100)
                );

                let allowAllValidator = await ethers.getContract(
                    "AllowAllValidator"
                );
                await this.protocolGovernance
                    .connect(this.admin)
                    .stageValidator(
                        this.weth.address,
                        allowAllValidator.address
                    );
                let uniV3Validator = await ethers.getContract("UniV3Validator");
                await this.protocolGovernance
                    .connect(this.admin)
                    .stageValidator(
                        this.swapRouter.address,
                        uniV3Validator.address
                    );
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitValidator(this.weth.address);
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitValidator(this.swapRouter.address);

                this.uniV3Oracle = await ethers.getContract("UniV3Oracle");

                await this.uniV3Oracle
                    .connect(this.admin)
                    .addUniV3Pools([await this.squeethVault.wPowerPerpPool()]);

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("temp", () => {
        it("deposits work", async () => {
            let baseWeth = await this.weth.balanceOf(this.squeethVault.address);
            expect(
                (await this.weth.balanceOf(this.depositor)).gt(
                    this.depositAmount
                )
            ).to.be.true;

            let deposited = BigNumber.from(0);
            await withSigner(this.depositor, async (s) => {
                deposited = (
                    await this.rootVault
                        .connect(s)
                        .callStatic.deposit(
                            [this.depositAmount],
                            0,
                            randomBytes(4)
                        )
                ).actualTokenAmounts[0];
                await this.rootVault
                    .connect(s)
                    .deposit([this.depositAmount], 0, randomBytes(4));
            });
            expect(
                (await this.weth.balanceOf(this.squeethVault.address)).eq(
                    deposited.add(baseWeth)
                )
            ).to.be.true;
        });
        it("withdraw does nothing without registering", async () => {
            await withSigner(this.depositor, async (s) => {
                await this.rootVault
                    .connect(s)
                    .deposit([this.depositAmount], 0, randomBytes(4));
                let wethBefore = await this.weth.balanceOf(this.depositor);
                await this.rootVault
                    .connect(s)
                    .withdraw(this.depositor, [randomBytes(4), randomBytes(4)]);
                expect(
                    (await this.weth.balanceOf(this.depositor)).eq(wethBefore)
                ).to.be.true;
            });
        });
        it("withdraws after registering", async () => {
            await withSigner(this.depositor, async (s) => {
                await this.rootVault
                    .connect(s)
                    .deposit([this.depositAmount], 0, randomBytes(4));
                let wethBefore = await this.weth.balanceOf(this.depositor);
                let lpAmount = await this.rootVault.balanceOf(this.depositor);
                await this.rootVault.connect(s).registerWithdrawal(lpAmount);
                await sleep(3600 * 24 * 30);
                await this.rootVault.connect(this.admin).invokeExecution();
                let withdrawn = await this.rootVault
                    .connect(s)
                    .callStatic.withdraw(this.depositor, [
                        randomBytes(4),
                        randomBytes(4),
                    ]);
                await this.rootVault
                    .connect(s)
                    .withdraw(this.depositor, [randomBytes(4), randomBytes(4)]);
                expect(
                    (await this.weth.balanceOf(this.depositor)).gt(wethBefore)
                ).to.be.true;
            });
        });
    });

    describe("full cycle", () => {
        beforeEach(async () => {
            await withSigner(this.depositor, async (s) => {
                await this.rootVault
                    .connect(s)
                    .deposit([this.depositAmount], 0, randomBytes(4));
            });
        });

        it("start", async () => {
            let currentEthPrice = await this.squeethVault.twapIndexPrice();
            let tvlBefore = await this.rootVault.tvl();
            await this.subject.startCycleMocked(
                currentEthPrice,
                BigNumber.from(10).pow(18).mul(100),
                this.safe,
                false
            );
            let tvlAfter = await this.rootVault.tvl();
            expect(tvlAfter[0][0].lt(tvlBefore[0][0])).to.be.true;
            expect(tvlAfter[1][0].lt(tvlBefore[1][0])).to.be.true;
        });

        it("option has no value", async () => {
            let currentEthPrice = await this.squeethVault.twapIndexPrice();

            let safeBalance = await this.weth.balanceOf(this.safe);
            await this.subject.startCycleMocked(
                currentEthPrice,
                BigNumber.from(10).pow(18).mul(100),
                this.safe,
                false
            );
            let newSafeBalance = await this.weth.balanceOf(this.safe);
            expect(newSafeBalance.gt(safeBalance)).to.be.true;

            let lpAmount = await this.rootVault.balanceOf(this.depositor);
            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).registerWithdrawal(lpAmount);
            });

            let previousEthPrice = await this.squeethVault.twapIndexPrice();
            await uniSwapTokensGivenInput(
                this.swapRouter,
                [this.usdc, this.weth],
                3000,
                true,
                BigNumber.from(10).pow(18).mul(1000)
            );
            await sleep(3600 * 24 * 30);
            let newEthPrice = await this.squeethVault.twapIndexPrice();
            expect(newEthPrice.lt(previousEthPrice)).to.be.true;
            await this.subject.endCycleMocked(this.safe);

            await withSigner(this.depositor, async (s) => {
                let withdrawn = await this.rootVault
                    .connect(s)
                    .callStatic.withdraw(this.depositor, [
                        randomBytes(4),
                        randomBytes(4),
                    ]);
                expect(withdrawn[0].lt(this.depositAmount.toString())).to.be
                    .true;
            });
        });
        it("crossing upper threshold", async () => {
            let currentEthPrice = await this.squeethVault.twapIndexPrice();

            let safeBalance = await this.weth.balanceOf(this.safe);
            let optionPrice = BigNumber.from(10).pow(18).mul(100);
            await this.subject.startCycleMocked(
                currentEthPrice,
                optionPrice,
                this.safe,
                false
            );
            let newSafeBalance = await this.weth.balanceOf(this.safe);
            expect(newSafeBalance.gt(safeBalance)).to.be.true;

            let lpAmount = await this.rootVault.balanceOf(this.depositor);
            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).registerWithdrawal(lpAmount);
            });

            await uniSwapTokensGivenInput(
                this.swapRouter,
                [this.usdc, this.weth],
                3000,
                false,
                BigNumber.from(10).pow(11).mul(500)
            );
            await uniSwapTokensGivenInput(
                this.swapRouter,
                [this.usdc, this.weth],
                3000,
                false,
                BigNumber.from(10).pow(11).mul(200)
            );
            await uniSwapTokensGivenInput(
                this.swapRouter,
                [this.usdc, this.weth],
                3000,
                false,
                BigNumber.from(10).pow(11).mul(200)
            );
            await uniSwapTokensGivenInput(
                this.swapRouter,
                [this.usdc, this.weth],
                3000,
                false,
                BigNumber.from(10).pow(11).mul(200)
            );

            await sleep(3600);

            let newEthPrice = await this.squeethVault.twapIndexPrice();
            expect(newEthPrice.gt(currentEthPrice)).to.be.true;

            let ONE = BigNumber.from(1e9);
            let optionPriceEth = ONE.mul(optionPrice).div(currentEthPrice);
            let priceMultiplicator = newEthPrice.mul(1e9).div(currentEthPrice);
            let shortMoney = this.depositAmount
                .mul(ONE)
                .div(ONE.add(optionPriceEth));
            let optionMoney = this.depositAmount.sub(shortMoney);
            let optionProfit = ONE.sub(ONE.mul(ONE).div(priceMultiplicator));
            let optionProfitETH = optionMoney
                .mul(optionProfit)
                .div(optionPriceEth);

            let toAllow = optionProfitETH.mul(11).div(10);

            await withSigner(this.safe, async (s) => {
                await this.weth
                    .connect(s)
                    .approve(this.squeethVault.address, toAllow);
            });

            await this.subject.endCycleMocked(this.safe);
        });

        it("crossing lower threshold", async () => {
            await this.subject.updateLiquidationParams({
                lowerLiquidationThresholdD9: BigNumber.from(10).pow(7).mul(95),
                upperLiquidationThresholdD9: BigNumber.from(10).pow(7).mul(180),
            });
            let currentEthPrice = await this.squeethVault.twapIndexPrice();

            let safeBalance = await this.weth.balanceOf(this.safe);
            await this.subject.startCycleMocked(
                currentEthPrice,
                BigNumber.from(10).pow(18).mul(100),
                this.safe,
                false
            );
            let newSafeBalance = await this.weth.balanceOf(this.safe);
            expect(newSafeBalance.gt(safeBalance)).to.be.true;

            let lpAmount = await this.rootVault.balanceOf(this.depositor);
            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).registerWithdrawal(lpAmount);
            });
            for (let i = 0; i < 3; i++) {
                await uniSwapTokensGivenInput(
                    this.swapRouter,
                    [this.usdc, this.weth],
                    3000,
                    true,
                    BigNumber.from(10).pow(18).mul(4000)
                );
                await sleep(3600);
            }
            let newEthPrice = await this.squeethVault.twapIndexPrice();
            expect(newEthPrice.lt(currentEthPrice)).to.be.true;
            await this.subject.endCycleMocked(this.safe);

            await withSigner(this.depositor, async (s) => {
                let withdrawn = await this.rootVault
                    .connect(s)
                    .callStatic.withdraw(this.depositor, [
                        randomBytes(4),
                        randomBytes(4),
                    ]);
                expect(withdrawn[0].lt(this.depositAmount.toString())).to.be
                    .true;
            });
        });

        it("option has value", async () => {
            let optionPrice = BigNumber.from(10).pow(18).mul(100);
            let currentEthPrice = await this.squeethVault.twapIndexPrice();
            await this.subject.startCycleMocked(
                currentEthPrice,
                optionPrice,
                this.safe,
                false
            );

            let lpAmount = await this.rootVault.balanceOf(this.depositor);
            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).registerWithdrawal(lpAmount);
            });

            await uniSwapTokensGivenInput(
                this.swapRouter,
                [this.usdc, this.weth],
                3000,
                false,
                BigNumber.from(10).pow(11).mul(500)
            );
            await sleep(3600 * 24 * 30);
            let newEthPrice = await this.squeethVault.twapIndexPrice();
            expect(newEthPrice.gt(currentEthPrice)).to.be.true;

            let ONE = BigNumber.from(1e9);
            let optionPriceEth = ONE.mul(optionPrice).div(currentEthPrice);
            let priceMultiplicator = newEthPrice.mul(1e9).div(currentEthPrice);
            let shortMoney = this.depositAmount
                .mul(ONE)
                .div(ONE.add(optionPriceEth));
            let optionMoney = this.depositAmount.sub(shortMoney);
            let optionProfit = ONE.sub(ONE.mul(ONE).div(priceMultiplicator));
            let optionProfitETH = optionMoney
                .mul(optionProfit)
                .div(optionPriceEth);

            let toAllow = optionProfitETH.mul(11).div(10);
            let atLeast = optionProfitETH.mul(9).div(10);

            await withSigner(this.safe, async (s) => {
                await this.weth
                    .connect(s)
                    .approve(this.squeethVault.address, toAllow);
            });
            let safeBalance = await this.weth.balanceOf(this.safe);
            await this.subject.endCycleMocked(this.safe);
            let newSafeBalance = await this.weth.balanceOf(this.safe);

            expect(safeBalance.sub(newSafeBalance).gt(atLeast)).to.be.true;
        });

        it("no money for second", async () => {
            await withSigner(this.safe, async (s) => {
                await this.weth
                    .connect(s)
                    .approve(
                        this.squeethVault.address,
                        BigNumber.from(10).pow(20)
                    );
            });

            let optionPrice = BigNumber.from(10).pow(18).mul(100);
            let currentEthPrice = await this.squeethVault.twapIndexPrice();
            await this.subject.startCycleMocked(
                currentEthPrice,
                optionPrice,
                this.safe,
                false
            );

            let lpAmount = await this.rootVault.balanceOf(this.depositor);
            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).registerWithdrawal(lpAmount);
            });

            await uniSwapTokensGivenInput(
                this.swapRouter,
                [this.usdc, this.weth],
                3000,
                false,
                BigNumber.from(10).pow(11).mul(500)
            );
            await sleep(3600 * 24 * 30);

            await this.subject.endCycleMocked(this.safe);

            await expect(
                this.subject.startCycleMocked(
                    currentEthPrice,
                    optionPrice,
                    this.safe,
                    false
                )
            ).to.be.revertedWith(Exceptions.LIMIT_UNDERFLOW);
        });

        it("two cycles", async () => {
            await withSigner(this.safe, async (s) => {
                await this.weth
                    .connect(s)
                    .approve(
                        this.squeethVault.address,
                        BigNumber.from(10).pow(20)
                    );
            });

            let optionPrice = BigNumber.from(10).pow(18).mul(100);
            let currentEthPrice = await this.squeethVault.twapIndexPrice();
            await this.subject.startCycleMocked(
                currentEthPrice,
                optionPrice,
                this.safe,
                false
            );

            let lpAmount = await this.rootVault.balanceOf(this.depositor);
            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).registerWithdrawal(lpAmount);
            });

            await uniSwapTokensGivenInput(
                this.swapRouter,
                [this.usdc, this.weth],
                3000,
                false,
                BigNumber.from(10).pow(11).mul(500)
            );
            await sleep(3600 * 24 * 30);

            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).cancelWithdrawal(lpAmount);
            });
            await this.subject.endCycleMocked(this.safe);

            let newEthPrice = await this.squeethVault.twapIndexPrice();
            await this.subject.startCycleMocked(
                newEthPrice,
                optionPrice,
                this.safe,
                false
            );

            await uniSwapTokensGivenInput(
                this.swapRouter,
                [this.usdc, this.weth],
                3000,
                false,
                BigNumber.from(10).pow(11).mul(200)
            );
            await sleep(3600 * 24 * 30);

            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).registerWithdrawal(lpAmount);
            });

            await this.subject.endCycleMocked(this.safe);
            await withSigner(this.depositor, async (s) => {
                let withdrawn = await this.rootVault
                    .connect(s)
                    .callStatic.withdraw(this.depositor, [
                        randomBytes(4),
                        randomBytes(4),
                    ]);
                expect(withdrawn[0].gt(this.depositAmount)).to.be.true;
            });
        });
    });
});
