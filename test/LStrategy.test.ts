import { expect } from "chai";
import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";

import { contract } from "./library/setup";
import { ERC20Vault, LStrategy, UniV3Vault } from "./types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { BigNumber } from "ethers";
import { combineVaults, setupVault } from "../deploy/0000_utils";
import Exceptions from "./library/Exceptions";

type CustomContext = {
    uniV3LowerVault: UniV3Vault;
    uniV3UpperVault: UniV3Vault;
    erc20Vault: ERC20Vault;
};

type DeployOptions = {};

contract<LStrategy, DeployOptions, CustomContext>("LStrategy", function () {
    const uniV3PoolFee = 3000;
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const { uniswapV3PositionManager, curveRouter, cowswap } =
                    await getNamedAccounts();

                this.cowswap = cowswap;

                this.positionManager = await ethers.getContractAt(
                    INonfungiblePositionManager,
                    uniswapV3PositionManager
                );

                this.preparePush = async ({
                    vault,
                    tickLower = -887220,
                    tickUpper = 887220,
                    usdcAmount = BigNumber.from(10).pow(6).mul(3000),
                    wethAmount = BigNumber.from(10).pow(18),
                }: {
                    vault: any;
                    tickLower?: number;
                    tickUpper?: number;
                    usdcAmount?: BigNumber;
                    wethAmount?: BigNumber;
                }) => {
                    const result = await mintUniV3Position_USDC_WETH({
                        fee: 3000,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        usdcAmount: usdcAmount,
                        wethAmount: wethAmount,
                    });
                    await this.positionManager.functions[
                        "safeTransferFrom(address,address,uint256)"
                    ](this.deployer.address, vault.address, result.tokenId);
                };

                const tokens = [this.weth.address, this.usdc.address]
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
                let deployParams = await deploy("LStrategy", {
                    from: this.deployer.address,
                    contract: "LStrategy",
                    args: [
                        uniswapV3PositionManager,
                        cowswap,
                        this.erc20Vault.address,
                        this.uniV3LowerVault.address,
                        this.uniV3UpperVault.address,
                        this.admin.address,
                    ],
                    log: true,
                    autoMine: true,
                });

                this.subject = await ethers.getContractAt(
                    "LStrategy",
                    deployParams.address
                );

                for (let address of [
                    this.deployer.address,
                    this.uniV3UpperVault.address,
                    this.uniV3LowerVault.address,
                    this.erc20Vault.address,
                ]) {
                    await mint(
                        "USDC",
                        address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );
                    await mint(
                        "WETH",
                        address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );
                    await this.weth.approve(
                        address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        address,
                        ethers.constants.MaxUint256
                    );
                }

                await this.subject.connect(this.admin).updateTradingParams({
                    maxSlippageD: BigNumber.from(10).pow(7),
                    oracleSafety: 5,
                    minRebalanceWaitTime: 86400,
                    orderDeadline: 86400 * 30,
                    oracle: this.mellowOracle.address,
                });

                await this.subject.connect(this.admin).updateRatioParams({
                    erc20UniV3CapitalRatioD: BigNumber.from(10).pow(7).mul(5), // 0.05 * DENOMINATOR,
                    erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5), // 0.5 * DENOMINATOR
                    minErc20UniV3CapitalRatioDeviationD:
                        BigNumber.from(10).pow(7),
                    minErc20TokenRatioDeviationD: BigNumber.from(10).pow(7),
                    minUniV3LiquidityRatioDeviationD: BigNumber.from(10).pow(7),
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

    describe.only("#targetPrice", () => {
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
                ))
            ).to.not.be.reverted;
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
                            [this.weth.address, this.usdc.address],
                            params
                        )
                    ).to.be.reverted;
                });
            });
            describe("when there is no existing pair", async () => {
                it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                    let params = {
                        maxSlippageD: BigNumber.from(10).pow(6),
                        minRebalanceWaitTime: 86400,
                        orderDeadline: 86400 * 30,
                        oracleSafety: 1,
                        oracle: ethers.constants.AddressZero,
                    };
                    await expect(
                        this.subject.targetPrice(
                            [this.weth.address, this.usdc.address],
                            params
                        )
                    ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                });
            });
        });
    });

    describe("#targetUniV3LiquidityRatio", () => {
        describe("returns target liquidity ratio", () => {
            describe("when target tick is more, than mid tick", () => {
                xit("returns isNegative false", async () => {
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    const result = await this.subject.targetUniV3LiquidityRatio(
                        1
                    );
                    expect(result.isNegative).to.be.false;
                    expect(result.liquidityRatioD).to.be.equal(
                        BigNumber.from(10)
                            .pow(9)
                            .div(887220 * 2)
                    ); // muldiv???????????????
                });
            });
            describe("when target tick is less, than mid tick", () => {
                xit("returns isNegative true", async () => {
                    await this.preparePush({ vault: this.uniV3LowerVault });
                    const result = await this.subject.targetUniV3LiquidityRatio(
                        -1
                    );
                    expect(result.isNegative).to.be.true;
                    expect(result.liquidityRatioD).to.be.equal(
                        BigNumber.from(10)
                            .pow(9)
                            .div(887220 * 2)
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
});
