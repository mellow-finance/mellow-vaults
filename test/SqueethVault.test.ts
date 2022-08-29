import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    randomAddress,
    sleep,
    withSigner,
    approxEqual,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20RootVault, ERC20Vault, SqueethVault } from "./types";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../deploy/0000_utils";
import { integrationVaultBehavior } from "./behaviors/integrationVault";
import {
    INTEGRATION_VAULT_INTERFACE_ID,
    SQUEETH_VAULT_INTERFACE_ID,
} from "./library/Constants";
import Exceptions from "./library/Exceptions";
import { assert } from "console";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<SqueethVault, DeployOptions, CustomContext>(
    "SqueethVault",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { read } = deployments;

                    const { curveRouter } = await getNamedAccounts();
                    this.curveRouter = curveRouter;
                    this.preparePush = async () => {
                        await sleep(0);
                    };

                    const tokens = [this.weth.address, this.squeeth.address]
                        .map((t) => t.toLowerCase())
                        .sort();

                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let erc20VaultNft = startNft;
                    let squeethVaultNft = erc20VaultNft + 1;
                    let erc20RootVaultNft = squeethVaultNft + 1;

                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );
                    await setupVault(
                        hre,
                        squeethVaultNft,
                        "SqueethVaultGovernance",
                        {
                            createVaultArgs: [this.deployer.address, true],
                        }
                    );

                    await combineVaults(
                        hre,
                        squeethVaultNft + 1,
                        [erc20VaultNft, squeethVaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );
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
                    const erc20RootVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20RootVaultNft
                    );

                    this.erc20Vault = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    );

                    this.subject = await ethers.getContractAt(
                        "SqueethVault",
                        squeethVault
                    );

                    this.erc20RootVault = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );

                    for (let address of [
                        this.deployer.address,
                        this.subject.address,
                        this.erc20Vault.address,
                    ]) {
                        await mint(
                            "WETH",
                            address,
                            BigNumber.from(10).pow(18).mul(3000)
                        );
                        await this.weth.approve(
                            address,
                            ethers.constants.MaxUint256
                        );
                    }

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#initialize", () => {
            beforeEach(async () => {
                this.nft = await ethers.provider.send("eth_getStorageAt", [
                    this.subject.address,
                    "0x4", // address of _nft
                ]);
                await ethers.provider.send("hardhat_setStorageAt", [
                    this.subject.address,
                    "0x4", // address of _nft
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                ]);
            });

            it("emits Initialized event", async () => {
                await withSigner(
                    this.squeethVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    [this.weth.address, this.squeeth.address],
                                    true
                                )
                        ).to.emit(this.subject, "Initialized");
                    }
                );
            });
            it("initializes contract successfully", async () => {
                await withSigner(
                    this.squeethVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    [this.weth.address, this.squeeth.address],
                                    true
                                )
                        ).to.not.be.reverted;
                    }
                );
            });

            describe("edge cases:", () => {
                describe("when vault's nft is not 0", () => {
                    it(`reverts with ${Exceptions.INIT}`, async () => {
                        await ethers.provider.send("hardhat_setStorageAt", [
                            this.subject.address,
                            "0x4", // address of _nft
                            "0x0000000000000000000000000000000000000000000000000000000000000001",
                        ]);
                        await expect(
                            this.subject.initialize(
                                this.nft,
                                [this.weth.address, this.squeeth.address],
                                true
                            )
                        ).to.be.revertedWith(Exceptions.INIT);
                    });
                });

                describe("not initialized when vault's nft is 0", () => {
                    it(`returns false`, async () => {
                        expect(await this.subject.initialized()).to.be.equal(
                            false
                        );
                    });
                });

                describe("when tokens are not sorted", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        await expect(
                            this.subject.initialize(
                                this.nft,
                                [this.squeeth.address, this.weth.address],
                                true
                            )
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });

                describe("when tokens are not unique", () => {
                    it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                        await expect(
                            this.subject.initialize(
                                this.nft,
                                [this.weth.address, this.weth.address],
                                true
                            )
                        ).to.be.revertedWith(Exceptions.INVARIANT);
                    });
                });

                describe("when setting zero nft", () => {
                    it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                        await expect(
                            this.subject.initialize(
                                0,
                                [this.weth.address, this.squeeth.address],
                                true
                            )
                        ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                    });
                });

                describe("when setting tokens.length != 2", () => {
                    it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                        await withSigner(
                            this.squeethVaultGovernance.address,
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(
                                            this.nft,
                                            [
                                                this.weth.address,
                                                this.squeeth.address,
                                                this.usdc.address,
                                            ],
                                            true
                                        )
                                ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                            }
                        );
                        await withSigner(
                            this.squeethVaultGovernance.address,
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(
                                            this.nft,
                                            [this.weth.address],
                                            true
                                        )
                                ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                            }
                        );
                    });
                });

                describe("when setting empty tokens array", () => {
                    it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                        await withSigner(
                            this.squeethVaultGovernance.address,
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(this.nft, [], true)
                                ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                            }
                        );
                    });
                });
                describe("when token has no permission to become a vault token", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await this.protocolGovernance
                            .connect(this.admin)
                            .revokePermissions(this.squeeth.address, [
                                PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                            ]);
                        await withSigner(
                            this.squeethVaultGovernance.address,
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(
                                            this.nft,
                                            [
                                                this.weth.address,
                                                this.squeeth.address,
                                            ],
                                            true
                                        )
                                ).to.be.revertedWith(Exceptions.FORBIDDEN);
                            }
                        );
                    });
                });
                describe("when tokens array is not equal to [weth, squeeth]", () => {
                    it(`reverts with ${Exceptions.INVALID_TOKEN}`, async () => {
                        let tokens = [this.weth.address, this.usdc.address]
                            .map((t) => t.toLowerCase())
                            .sort();

                        await withSigner(
                            this.squeethVaultGovernance.address,
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(this.nft, tokens, true)
                                ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                            }
                        );
                        tokens = [this.squeeth.address, this.usdc.address]
                            .map((t) => t.toLowerCase())
                            .sort();
                        await withSigner(
                            this.squeethVaultGovernance.address,
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(this.nft, tokens, true)
                                ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                            }
                        );
                        tokens = [this.dai.address, this.usdc.address]
                            .map((t) => t.toLowerCase())
                            .sort();
                        await withSigner(
                            this.squeethVaultGovernance.address,
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(this.nft, tokens, true)
                                ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                            }
                        );
                    });
                });
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true if this contract supports ${SQUEETH_VAULT_INTERFACE_ID} interface`, async () => {
                expect(
                    await this.subject.supportsInterface(
                        SQUEETH_VAULT_INTERFACE_ID
                    )
                ).to.be.true;
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .supportsInterface(
                                    INTEGRATION_VAULT_INTERFACE_ID
                                )
                        ).to.not.be.reverted;
                    });
                });
            });
        });

        describe("#controller", () => {
            it("returns squeeth controller", async () => {
                const { squeethController } = await getNamedAccounts();
                expect(await this.subject.controller()).to.be.equal(
                    squeethController
                );
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(this.subject.controller()).to.not.be
                            .reverted;
                    });
                });
            });
        });

        describe("#router", () => {
            it("returns univ3 swap router", async () => {
                const { uniswapV3Router } = await getNamedAccounts();
                expect(await this.subject.router()).to.be.equal(
                    uniswapV3Router
                );
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(this.subject.router()).to.not.be.reverted;
                    });
                });
            });
        });

        describe("#takeLong", () => {
            let one: BigNumber = BigNumber.from(10).pow(18);
            let wethAmountIn = one.mul(64);
            let minWPowerPerpAmountOut = 0;
            beforeEach(async () => {
                let nft = Number(await this.vaultRegistry.vaultsCount()) + 1;

                await setupVault(hre, nft, "SqueethVaultGovernance", {
                    createVaultArgs: [this.deployer.address, false],
                });
                const squeethVault = await this.vaultRegistry.vaultForNft(nft);
                this.subject = await ethers.getContractAt(
                    "SqueethVault",
                    squeethVault
                );

                await this.weth.approve(this.subject.address, wethAmountIn);
            });

            it("gets squeeth wPowerPerp tokens from the oSQTH/WETH pool", async () => {
                let { wPowerPerpAmount: initialAmount } =
                    await this.subject.longPositionInfo();
                assert(initialAmount.eq(0));

                await expect(
                    this.subject
                        .connect(this.deployer)
                        .takeLong(wethAmountIn, minWPowerPerpAmountOut)
                ).to.not.be.reverted;

                await this.weth.approve(this.subject.address, 0);

                let { wPowerPerpAmount } =
                    await this.subject.longPositionInfo();

                expect(wPowerPerpAmount.gt(0)).to.be.true;

                let usdcSqthSqrtPrice = await this.subject.getSpotSqrtPrice();
                let usdcWethPow2SqrtPrice =
                    await this.subject.getSqrtIndexPrice();
                let Q192 = BigNumber.from(2).pow(192);

                let usdcSqthPrice = usdcSqthSqrtPrice.pow(2).div(Q192);
                let usdcWethPow2Price = usdcWethPow2SqrtPrice.pow(2).div(Q192);

                // delta is less than or equal 5% wethAmountIn
                let eps = BigNumber.from(5);
                expect(
                    await approxEqual(
                        wethAmountIn,
                        usdcSqthPrice
                            .mul(wPowerPerpAmount)
                            .div(usdcWethPow2Price),
                        eps
                    )
                ).to.be.true;
            });

            it("multiple takeLong calls increse total wPowerPerp received amount", async () => {
                let { wPowerPerpAmount: initialAmount } =
                    await this.subject.longPositionInfo();
                assert(initialAmount.eq(0));
                const wPowerPerpAmountFirst = await this.subject
                    .connect(this.deployer)
                    .callStatic.takeLong(wethAmountIn, minWPowerPerpAmountOut);
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .takeLong(wethAmountIn, minWPowerPerpAmountOut)
                ).to.not.be.reverted;

                await this.weth.approve(this.subject.address, wethAmountIn);
                const wPowerPerpAmountSecond = await this.subject
                    .connect(this.deployer)
                    .callStatic.takeLong(wethAmountIn, minWPowerPerpAmountOut);
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .takeLong(wethAmountIn, minWPowerPerpAmountOut)
                ).to.not.be.reverted;

                let { wPowerPerpAmount } =
                    await this.subject.longPositionInfo();

                expect(wPowerPerpAmount).to.be.eq(
                    wPowerPerpAmountFirst.add(wPowerPerpAmountSecond)
                );
            });

            it("emits LongTaken event", async () => {
                await expect(
                    this.subject
                        .connect(this.deployer)
                        .takeLong(wethAmountIn, minWPowerPerpAmountOut)
                ).to.emit(this.subject, "LongTaken");
            });

            describe("access control:", () => {
                it("allowed: vault owner", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .takeLong(wethAmountIn, minWPowerPerpAmountOut)
                    ).to.not.be.reverted;
                });
                it("allowed: approved account", async () => {
                    let account = randomAddress();
                    let nft = Number(await this.vaultRegistry.vaultsCount());
                    await this.vaultRegistry
                        .connect(this.deployer)
                        .approve(account, nft);
                    await this.weth
                        .connect(this.deployer)
                        .transfer(account, wethAmountIn);
                    await withSigner(account, async (s) => {
                        await this.weth
                            .connect(s)
                            .approve(this.subject.address, wethAmountIn);
                        await expect(
                            this.subject
                                .connect(s)
                                .takeLong(wethAmountIn, minWPowerPerpAmountOut)
                        ).to.not.be.reverted;
                    });
                });
                it("denied: other address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .takeLong(wethAmountIn, minWPowerPerpAmountOut)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });

            describe("edge cases:", () => {
                describe("when position is short", () => {
                    it(`reverts with ${Exceptions.INVALID_STATE}`, async () => {
                        let nft =
                            Number(await this.vaultRegistry.vaultsCount()) + 1;

                        await setupVault(hre, nft, "SqueethVaultGovernance", {
                            createVaultArgs: [this.deployer.address, true],
                        });
                        const squeethVault =
                            await this.vaultRegistry.vaultForNft(nft);
                        this.subject = await ethers.getContractAt(
                            "SqueethVault",
                            squeethVault
                        );

                        await expect(
                            this.subject
                                .connect(this.deployer)
                                .takeLong(wethAmountIn, minWPowerPerpAmountOut)
                        ).to.be.revertedWith(Exceptions.INVALID_STATE);
                    });
                });

                describe("when wethAmountIn is less than or equal dust amount of squeeth vault", () => {
                    it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                        let newWethAmountIn = (await this.subject.DUST()).sub(
                            1
                        );
                        await expect(
                            this.subject
                                .connect(this.deployer)
                                .takeLong(
                                    newWethAmountIn,
                                    minWPowerPerpAmountOut
                                )
                        ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                    });
                });

                describe("when wethAmountIn is greater than balance of msg.sender", () => {
                    it(`reverts with ${Exceptions.LIMIT_OVERFLOW}`, async () => {
                        let newWethAmountIn = (
                            await this.weth.balanceOf(this.deployer.address)
                        ).add(1);
                        await expect(
                            this.subject
                                .connect(this.deployer)
                                .takeLong(
                                    newWethAmountIn,
                                    minWPowerPerpAmountOut
                                )
                        ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                    });
                });

                describe("when wethAmountIn is greater than allowance from msg.sender to squeethVault", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await this.weth.approve(
                            this.subject.address,
                            wethAmountIn.sub(1)
                        );
                        await expect(
                            this.subject
                                .connect(this.deployer)
                                .takeLong(wethAmountIn, minWPowerPerpAmountOut)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#closeLong", () => {
            let one: BigNumber = BigNumber.from(10).pow(18);
            let minWethAmountOut = 0;
            let dust: BigNumber;
            beforeEach(async () => {
                let nft = Number(await this.vaultRegistry.vaultsCount()) + 1;

                await setupVault(hre, nft, "SqueethVaultGovernance", {
                    createVaultArgs: [this.deployer.address, false],
                });
                const squeethVault = await this.vaultRegistry.vaultForNft(nft);
                this.subject = await ethers.getContractAt(
                    "SqueethVault",
                    squeethVault
                );

                let wethAmountIn = one.mul(64);
                let minWPowerPerpAmountOut = 0;

                await this.weth.approve(this.subject.address, wethAmountIn);

                await this.subject
                    .connect(this.deployer)
                    .takeLong(wethAmountIn, minWPowerPerpAmountOut);

                await this.weth.approve(this.subject.address, 0);
                dust = await this.subject.DUST();
            });
            it("sells squeeth wPowerPerp tokens back to the oSQTH/WETH pool", async () => {
                let { wPowerPerpAmount: initialAmount } =
                    await this.subject.longPositionInfo();
                assert(initialAmount.gt(dust));
                await this.subject.closeLong(initialAmount, minWethAmountOut);

                let { wPowerPerpAmount: latestAmount } =
                    await this.subject.longPositionInfo();
                // 1% >= deviation
                expect(
                    approxEqual(
                        latestAmount,
                        BigNumber.from(0),
                        BigNumber.from(1)
                    )
                );

                let vaultSqthBalance = await this.squeeth.balanceOf(
                    this.subject.address
                );
                expect(vaultSqthBalance.lte(dust));
            });

            it("multiple closeLong calls decrese total wPowerPerp amount aquired by the user", async () => {
                let { wPowerPerpAmount: initialAmount } =
                    await this.subject.longPositionInfo();
                assert(initialAmount.gt(dust));

                await this.subject.closeLong(
                    initialAmount.div(2),
                    minWethAmountOut
                );
                await this.subject.closeLong(
                    initialAmount.div(2),
                    minWethAmountOut
                );

                let { wPowerPerpAmount: latestAmount } =
                    await this.subject.longPositionInfo();
                // 1% >= deviation
                expect(
                    approxEqual(
                        latestAmount,
                        BigNumber.from(0),
                        BigNumber.from(1)
                    )
                );

                let vaultSqthBalance = await this.squeeth.balanceOf(
                    this.subject.address
                );
                expect(vaultSqthBalance.lte(dust));
            });

            it("emits LongClosed event", async () => {
                let { wPowerPerpAmount: initialAmount } =
                    await this.subject.longPositionInfo();
                assert(initialAmount.gt(dust));

                await expect(
                    this.subject
                        .connect(this.deployer)
                        .closeLong(initialAmount, minWethAmountOut)
                ).to.emit(this.subject, "LongClosed");
            });

            describe("access control:", () => {
                it("allowed: vault owner", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .closeLong(dust.add(1), minWethAmountOut)
                    ).to.not.be.reverted;
                });
                it("allowed: approved account", async () => {
                    let account = randomAddress();
                    let nft = Number(await this.vaultRegistry.vaultsCount());
                    await this.vaultRegistry
                        .connect(this.deployer)
                        .approve(account, nft);
                    await withSigner(account, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .closeLong(dust.add(1), minWethAmountOut)
                        ).to.not.be.reverted;
                    });
                });
                it("denied: other address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .closeLong(dust.add(1), minWethAmountOut)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });

            describe("edge cases:", () => {
                describe("when position is short", () => {
                    it(`reverts with ${Exceptions.INVALID_STATE}`, async () => {
                        let nft =
                            Number(await this.vaultRegistry.vaultsCount()) + 1;

                        await setupVault(hre, nft, "SqueethVaultGovernance", {
                            createVaultArgs: [this.deployer.address, true],
                        });
                        const squeethVault =
                            await this.vaultRegistry.vaultForNft(nft);
                        this.subject = await ethers.getContractAt(
                            "SqueethVault",
                            squeethVault
                        );

                        await expect(
                            this.subject
                                .connect(this.deployer)
                                .closeLong(dust.add(1), minWethAmountOut)
                        ).to.be.revertedWith(Exceptions.INVALID_STATE);
                    });
                });

                describe("when wPowerPerpAmount is less than or equal dust amount of squeeth vault", () => {
                    it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                        let newWPowerPerpAmount = (
                            await this.subject.DUST()
                        ).sub(1);
                        await expect(
                            this.subject
                                .connect(this.deployer)
                                .closeLong(
                                    newWPowerPerpAmount,
                                    minWethAmountOut
                                )
                        ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                    });
                });

                describe("when wPowerPerpAmount is greater than balance of squeeth vault", () => {
                    it(`reverts with ${Exceptions.LIMIT_OVERFLOW}`, async () => {
                        let newWPowerPerpAmount = (
                            await this.squeeth.balanceOf(this.subject.address)
                        ).add(1);
                        await expect(
                            this.subject
                                .connect(this.deployer)
                                .closeLong(
                                    newWPowerPerpAmount,
                                    minWethAmountOut
                                )
                        ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                    });
                });
            });
        });

        // describe.only("write", () => {
        //     it("", async () => {
        //         console.log(await this.subject.write());
        //     });
        // });

        describe.only("#takeShort", () => {
            let one: BigNumber = BigNumber.from(10).pow(18);
            let dust: BigNumber;
            beforeEach(async () => {
                let nft = Number(await this.vaultRegistry.vaultsCount()) + 1;

                await setupVault(hre, nft, "SqueethVaultGovernance", {
                    createVaultArgs: [this.deployer.address, true],
                });
                const squeethVault = await this.vaultRegistry.vaultForNft(nft);
                this.subject = await ethers.getContractAt(
                    "SqueethVault",
                    squeethVault
                );

                dust = await this.subject.DUST();
            });

            it("mints wPowerPerp using weth as a collateral, than immediately sells wPowerPerp to the oSQTH/WETH univ3 pool", async () => {
                let wPowerPerpExpectedAmount = one.mul(1);
                let wethDebtAmount = one.mul(10);
                let minWethAmountOut = BigNumber.from(0);
                await this.weth.approve(this.subject.address, wethDebtAmount);
                let {wPowerPerpMintedAmount, wethAmountOut} = await this.subject.callStatic.takeShort(wPowerPerpExpectedAmount, wethDebtAmount, minWethAmountOut);
                await this.subject.takeShort(wPowerPerpExpectedAmount, wethDebtAmount, minWethAmountOut);
                let {wPo} = await this.subject.shortPositionInfo();
                expect()
            });
        });

        //integrationVaultBehavior.call(this, {});
    }
);
