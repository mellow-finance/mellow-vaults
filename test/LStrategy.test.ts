import { expect } from "chai";
import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";

import { contract } from "./library/setup";
import { ERC20Vault, LStrategy, MockCowswap, UniV3Vault } from "./types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { abi as ICurvePool } from "./helpers/curvePoolABI.json";
import { abi as IWETH } from "./helpers/wethABI.json";
import { abi as IWSTETH } from "./helpers/wstethABI.json";
import {
    mint,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { BigNumber } from "ethers";
import {combineVaults, PermissionIdsLibrary, setupVault} from "../deploy/0000_utils";
import Exceptions from "./library/Exceptions";
import { ERC20 } from "./library/Types";
import { randomBytes } from "ethers/lib/utils";

type CustomContext = {
    uniV3LowerVault: UniV3Vault;
    uniV3UpperVault: UniV3Vault;
    erc20Vault: ERC20Vault;
    cowswap: MockCowswap;
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
                        await tokenIn.connect(senderSigner).approve(
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
                        await this.swapRouter.connect(senderSigner).exactInputSingle(params);
                    });
                };

                await this.weth.approve(
                    uniswapV3PositionManager,
                    ethers.constants.MaxUint256
                );
                await this.wsteth.approve(
                    uniswapV3PositionManager,
                    ethers.constants.MaxUint256
                )

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
                    }
                    const result = await this.positionManager.callStatic.mint(mintParams);
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

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft, uniV3LowerVaultNft, uniV3UpperVaultNft],
                    this.deployer.address,
                    this.deployer.address
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
                const erc20RootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft + 1
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

                this.erc20RootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVault
                );

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
                let strategyDeployParams = await deploy("LStrategy", {
                    from: this.deployer.address,
                    contract: "LStrategy",
                    args: [
                        uniswapV3PositionManager,
                        cowswapDeployParams.address,
                        this.erc20Vault.address,
                        this.uniV3LowerVault.address,
                        this.uniV3UpperVault.address,
                        this.admin.address,
                    ],
                    log: true,
                    autoMine: true,
                });

                let cowswapValidatorDeployParams = await deploy("CowswapValidator", {
                    from: this.deployer.address,
                    contract: "CowswapValidator",
                    args: [this.protocolGovernance.address],
                    log: true,
                    autoMine: true,
                });

                await this.protocolGovernance.connect(this.admin).stageValidator(this.cowswap.address, cowswapValidatorDeployParams.address);
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.protocolGovernance.connect(this.admin).commitValidator(this.cowswap.address);

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
                    0, 1, BigNumber.from(10).pow(18).mul(2000), ethers.constants.Zero, options
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

                let oracleDeployParams = await deploy("MockOracle", {
                    from: this.deployer.address,
                    contract: "MockOracle",
                    args: [],
                    log: true,
                    autoMine: true,
                });

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
                    minErc20TokenRatioDeviationD: BigNumber.from(10).pow(8).div(2),
                    minUniV3LiquidityRatioDeviationD: BigNumber.from(10).pow(8).div(2),
                });

                await this.subject.connect(this.admin).updateOtherParams({
                    intervalWidthInTicks: 100,
                    minToken0ForOpening: BigNumber.from(10).pow(6),
                    minToken1ForOpening: BigNumber.from(10).pow(6),
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
                    params.maxSlippageD = BigNumber.from(10).pow(10);
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
                BigNumber.from(10).pow(7).mul(5),
                BigNumber.from(10).pow(8).mul(5),
                BigNumber.from(10).pow(7),
                BigNumber.from(10).pow(7),
                BigNumber.from(10).pow(7),
            ];
            const returnedParams = await this.subject.ratioParams();
            expect(expectedParams == returnedParams);
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
                    params.erc20UniV3CapitalRatioD = BigNumber.from(10).pow(10);
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
                    params.erc20TokenRatioD = BigNumber.from(10).pow(10);
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
                oracle: this.mellowOracle.address,
            };
            expect(
                (await this.subject.targetPrice(
                    [this.weth.address, this.usdc.address],
                    params
                )).shr(96)
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
                            [this.usdc.address, this.weth.address],
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
                        BigNumber.from(10)
                            .pow(9)
                            .div(887220)
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
                        BigNumber.from(10)
                            .pow(9)
                            .div(887220)
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
                await this.usdc.connect(signer).approve(this.cowswap.address, BigNumber.from(10).pow(18));
            });
            await this.grantPermissions();
            await this.subject.connect(this.admin).grantRole(await this.subject.ADMIN_DELEGATE_ROLE(), this.deployer.address);
            await this.subject.resetCowswapAllowance(0);
            expect(await this.usdc.allowance(this.erc20Vault.address, this.cowswap.address)).to.be.equal(0);
        });
        it("emits CowswapAllowanceReset event", async () => {
            await this.grantPermissions();
            await this.subject.connect(this.admin).grantRole(await this.subject.ADMIN_DELEGATE_ROLE(), this.deployer.address);
            await expect(this.subject.resetCowswapAllowance(0)).to.emit(this.subject, "CowswapAllowanceReset");
        });

        describe("edge cases:", () => {
            describe("when permissions are not set", () => {
                it("reverts", async () => {
                    await expect(this.subject.connect(this.admin).resetCowswapAllowance(0)).to.be.reverted;
                });
            });
        });

        describe("access control:", () => {
            it("allowed: admin", async () => {
                await this.grantPermissions();
                await expect(this.subject.connect(this.admin).resetCowswapAllowance(0)).to.not.be.reverted;
            });
            it("allowed: operator", async () => {
                await this.grantPermissions();
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject.connect(this.admin).grantRole(await this.subject.ADMIN_DELEGATE_ROLE(), signer.address);
                    await expect(this.subject.connect(signer).resetCowswapAllowance(0)).to.not.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await this.grantPermissions();
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).resetCowswapAllowance(0)).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });
    });

    describe("#collectUniFees", () => {
        it("collect fees from both univ3 vaults", async () => {
            await this.preparePush({vault: this.uniV3LowerVault});
            await this.preparePush({vault: this.uniV3UpperVault});
            await this.uniV3UpperVault.push(
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                []
            )
            await this.uniV3LowerVault.push(
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                []
            )
            await this.swapTokens(this.deployer.address, this.deployer.address, this.usdc, this.weth, BigNumber.from(10).pow(6).mul(5000));

            let lowerVaultFees = await this.uniV3LowerVault.callStatic.collectEarnings();
            let upperVaultFees = await this.uniV3UpperVault.callStatic.collectEarnings();
            for (let i = 0; i < 2; ++i) {
                lowerVaultFees[i].add(upperVaultFees[i]);
            }
            let sumFees = await this.subject.connect(this.admin).callStatic.collectUniFees();
            expect(sumFees == lowerVaultFees);
            await expect(this.subject.connect(this.admin).collectUniFees()).to.not.be.reverted;
        });
        it("emits FeesCollected event", async () => {
            await this.preparePush({vault: this.uniV3LowerVault});
            await this.preparePush({vault: this.uniV3UpperVault});
            await expect(this.subject.connect(this.admin).collectUniFees()).to.emit(this.subject, "FeesCollected");
        });

        describe("edge cases:", () => {
            describe("when there is no minted position", () => {
               it("reverts", async () => {
                   await expect(this.subject.connect(this.admin).collectUniFees()).to.be.reverted;
               });
            });
            describe("when there were no swaps", () => {
                it("returns zeroes", async () => {
                    await this.preparePush({vault: this.uniV3LowerVault});
                    await this.preparePush({vault: this.uniV3UpperVault});
                    await this.uniV3UpperVault.push(
                        [this.usdc.address, this.weth.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(10).pow(18).mul(1),
                        ],
                        []
                    )
                    await this.uniV3LowerVault.push(
                        [this.usdc.address, this.weth.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(10).pow(18).mul(1),
                        ],
                        []
                    )

                    let lowerVaultFees = await this.uniV3LowerVault.callStatic.collectEarnings();
                    let upperVaultFees = await this.uniV3UpperVault.callStatic.collectEarnings();
                    for (let i = 0; i < 2; ++i) {
                        lowerVaultFees[i].add(upperVaultFees[i]);
                    }
                    let sumFees = await this.subject.connect(this.admin).callStatic.collectUniFees();
                    expect(sumFees == [ethers.constants.Zero, ethers.constants.Zero]);
                    await expect(this.subject.connect(this.admin).collectUniFees()).to.not.be.reverted;
                });
            });
        });

        describe("access control:", () => {
            it("allowed: admin", async () => {
                await this.preparePush({vault: this.uniV3LowerVault});
                await this.preparePush({vault: this.uniV3UpperVault});
                await expect(this.subject.connect(this.admin).collectUniFees()).to.not.be.reverted;
            });
            it("allowed: operator", async() => {
                await this.preparePush({vault: this.uniV3LowerVault});
                await this.preparePush({vault: this.uniV3UpperVault});
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject.connect(this.admin).grantRole(await this.subject.ADMIN_DELEGATE_ROLE(), signer.address);
                    await expect(this.subject.connect(signer).collectUniFees()).to.not.be.reverted;
                });
            });
            it("not allowed: any address", async() => {
                await this.preparePush({vault: this.uniV3LowerVault});
                await this.preparePush({vault: this.uniV3UpperVault});
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).collectUniFees()).to.be.reverted;
                });
            });
        });
    });

    describe("#manualPull", () => {
        beforeEach(async () => {
            await withSigner(this.erc20Vault.address, async (signer) => {
                await this.usdc.connect(signer).approve(this.uniV3UpperVault.address, ethers.constants.MaxUint256);
            });
        });

        it("pulls tokens from one vault to another", async () => {
            await this.grantPermissions();
            await this.subject.connect(this.admin).manualPull(
                this.erc20Vault.address,
                this.uniV3UpperVault.address,
                [BigNumber.from(10).pow(18).mul(3000), BigNumber.from(10).pow(18).mul(3000)],
                [ethers.constants.Zero, ethers.constants.Zero],
                ethers.constants.MaxUint256
            );
            let endBalances = [
                [await this.usdc.balanceOf(this.erc20Vault.address), await this.weth.balanceOf(this.erc20Vault.address)],
                [await this.usdc.balanceOf(this.uniV3UpperVault.address), await this.weth.balanceOf(this.uniV3UpperVault.address)],
            ]
            expect(endBalances == [
                [BigNumber.from(10).pow(18).mul(6000), BigNumber.from(10).pow(18).mul(6000)],
                [ethers.constants.Zero, ethers.constants.Zero]
            ])
        });
        it("emits ManualPull event", async () => {
            await this.grantPermissions();
            await expect(this.subject.connect(this.admin).manualPull(
                this.erc20Vault.address,
                this.uniV3UpperVault.address,
                [BigNumber.from(10).pow(6).mul(3000), BigNumber.from(10).pow(18).mul(1)],
                [ethers.constants.Zero, ethers.constants.Zero],
                ethers.constants.MaxUint256
            )).to.emit(this.subject, "ManualPull");
        });

        describe("access control:", () => {
            it("allowed: admin", async () => {
                await this.grantPermissions();
                await this.subject.connect(this.admin).manualPull(
                    this.erc20Vault.address,
                    this.uniV3UpperVault.address,
                    [BigNumber.from(10).pow(6).mul(3000), BigNumber.from(10).pow(18).mul(1)],
                    [ethers.constants.Zero, ethers.constants.Zero],
                    ethers.constants.MaxUint256
                );
            });
            it("not allowed: operator", async() => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject.connect(this.admin).grantRole(await this.subject.ADMIN_DELEGATE_ROLE(), signer.address);
                    await expect(this.subject.connect(signer).manualPull(
                        this.erc20Vault.address,
                        this.uniV3UpperVault.address,
                        [BigNumber.from(10).pow(6).mul(3000), BigNumber.from(10).pow(18).mul(1)],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    )).to.be.reverted;
                });
            });
            it("not allowed: any address", async() => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).manualPull(
                        this.erc20Vault.address,
                        this.uniV3UpperVault.address,
                        [BigNumber.from(10).pow(6).mul(3000), BigNumber.from(10).pow(18).mul(1)],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    )).to.be.reverted;
                });
            });
        });
    });

    describe("#rebalanceERC20UniV3Vaults", () => {
        describe("access control:", () => {
            beforeEach(async () => {
                await this.preparePush({vault: this.uniV3LowerVault});
                await this.preparePush({vault: this.uniV3UpperVault});
            });

            it("allowed: admin", async () => {
                await this.subject.connect(this.admin).rebalanceERC20UniV3Vaults(
                    [ethers.constants.Zero, ethers.constants.Zero],
                    [ethers.constants.Zero, ethers.constants.Zero],
                    ethers.constants.MaxUint256
                );
            });
            it("not allowed: operator", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject.connect(this.admin).grantRole(await this.subject.ADMIN_DELEGATE_ROLE(), signer.address);
                    await expect(this.subject.connect(signer).rebalanceERC20UniV3Vaults(
                        [ethers.constants.Zero, ethers.constants.Zero],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    )).to.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).rebalanceERC20UniV3Vaults(
                        [ethers.constants.Zero, ethers.constants.Zero],
                        [ethers.constants.Zero, ethers.constants.Zero],
                        ethers.constants.MaxUint256
                    )).to.be.reverted;
                });
            });
        });
    });

    xdescribe("#rebalanceUniV3Vaults", () => {});

    describe("#postPreOrder", () => {
        it("initializing preOrder when liquidityDelta is negative", async () => {
            await this.subject.connect(this.admin).postPreOrder();
            await expect((await this.subject.preOrder()).tokenIn).eq(this.weth.address);
        });
        it("initializing preOrder when liquidityDelta is not negative", async () => {
            await withSigner(this.erc20Vault.address, async (signer) => {
                await this.weth.connect(signer).transfer(this.deployer.address, BigNumber.from(10).pow(18).mul(500));
            });
            await this.subject.connect(this.admin).postPreOrder();
            await expect((await this.subject.preOrder()).tokenIn).eq(this.wsteth.address);
        });
        it("emits PreOrderPosted event", async () => {
            await expect(this.subject.connect(this.admin).postPreOrder()).to.emit(this.subject, "PreOrderPosted");
        });

        describe("edge cases:", () => {
            describe("when orderDeadline is lower than block.timestamp", () => {
                it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
                    //?????????????????????????????????
                    console.log(await ethers.provider.send("eth_getStorageAt", [
                        this.subject.address,
                        "0xa", // address of orderDeadline
                    ]));
                    await ethers.provider.send("hardhat_setStorageAt", [
                        this.subject.address,
                        "0xa", // address of orderDeadline
                        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                    ]);
                    await expect(this.subject.connect(this.admin).postPreOrder()).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });

        describe("access control:", () => {
            it("allowed: admin", async () => {
                await expect(this.subject.connect(this.admin).postPreOrder()).to.not.be.reverted;
            });
            it("allowed: operator", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.subject.connect(this.admin).grantRole(await this.subject.ADMIN_DELEGATE_ROLE(), signer.address);
                    await expect(this.subject.connect(signer).postPreOrder()).to.not.be.reverted;
                });
            });
            it("not allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).postPreOrder()).to.be.reverted;
                });
            });
        });
    });

    describe.only("#signOrder", () => {
        beforeEach(async () => {
            this.successfulInitialization = async () => {
                await this.grantPermissions();
                await this.subject.connect(this.admin).postPreOrder();
                let preOrder = await this.subject.preOrder();
                this.baseOrderStruct = {
                    sellToken: preOrder.tokenIn,
                    buyToken: preOrder.tokenOut,
                    receiver: this.deployer.address,
                    sellAmount: preOrder.amountIn,
                    buyAmount: preOrder.minAmountOut,
                    validTo: preOrder.deadline,
                    appData: randomBytes(32),
                    feeAmount: BigNumber.from(500),
                    kind: randomBytes(32),
                    partiallyFillable: false,
                    sellTokenBalance: randomBytes(32),
                    buyTokenBalance: randomBytes(32)
                };
            };
        });
        it("signs order successfully when signed is set to true", async () => {
            await this.successfulInitialization();
            let orderHash = await this.cowswap.callStatic.hash(this.baseOrderStruct, await this.cowswap.domainSeparator());
            let orderUuid = ethers.utils.solidityPack(["bytes32", "address", "uint32"], [orderHash, randomBytes(20), randomBytes(4)]);
            await expect(this.subject.connect(this.admin).signOrder(this.baseOrderStruct, orderUuid, true));
            expect(await this.subject.orderDeadline()).eq(this.baseOrderStruct.validTo);
            expect(await this.cowswap.preSignature(orderUuid)).to.be.true;
        });
        it("resets order successfully when signed is set to false", async () => {
            await this.successfulInitialization();
            let orderHash = await this.cowswap.callStatic.hash(this.baseOrderStruct, await this.cowswap.domainSeparator());
            let orderUuid = ethers.utils.solidityPack(["bytes32", "address", "uint32"], [orderHash, randomBytes(20), randomBytes(4)]);
            await expect(this.subject.connect(this.admin).signOrder(this.baseOrderStruct, orderUuid, false));
            expect(await this.cowswap.preSignature(orderUuid)).to.be.false;
        });
        it("emits OrderSigned event", async () => {
            await this.successfulInitialization();
            let orderHash = await this.cowswap.callStatic.hash(this.baseOrderStruct, await this.cowswap.domainSeparator());
            await expect(this.subject.connect(this.admin).signOrder(this.baseOrderStruct, ethers.utils.solidityPack(["bytes32", "address", "uint32"], [orderHash, randomBytes(20), randomBytes(4)]), true)).to.emit(this.subject, "OrderSigned");
        });
    });
});