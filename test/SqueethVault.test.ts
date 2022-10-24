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

                    this.preparePush = async () => {
                        await sleep(0);
                    };

                    const {
                        curveRouter
                    } = await getNamedAccounts();
                    this.curveRouter = curveRouter;

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
                            createVaultArgs: [this.deployer.address],
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
                        this.subject.address
                    ]) {
                        await mint(
                            "WETH",
                            address,
                            BigNumber.from(10).pow(18).mul(10)
                        );
                        await this.weth.approve(
                            address,
                            ethers.constants.MaxUint256
                        );
                    }
                    this.healthFactor = BigNumber.from(10).pow(9).mul(2);
                    this.squeethVaultNft = squeethVaultNft;

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
                                    [this.weth.address]
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
                                    [this.weth.address]
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
                                [this.weth.address]
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

                describe("when there are two tokens", () => {
                    it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                        await expect(
                            this.subject.initialize(
                                this.nft,
                                [this.weth.address, this.squeeth.address]
                            )
                        ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                    });
                });

                describe("when setting zero nft", () => {
                    it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                        await expect(
                            this.subject.initialize(
                                0,
                                [this.weth.address]
                            )
                        ).to.be.revertedWith(Exceptions.VALUE_ZERO);
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
                                        .initialize(this.nft, [])
                                ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                            }
                        );
                    });
                });
                describe("when token has no permission to become a vault token", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await this.protocolGovernance
                            .connect(this.admin)
                            .revokePermissions(this.weth.address, [
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
                                                this.weth.address
                                            ]
                                        )
                                ).to.be.revertedWith(Exceptions.FORBIDDEN);
                            }
                        );
                    });
                });
                describe("when tokens array is not equal to [weth]", () => {
                    it(`reverts with ${Exceptions.INVALID_TOKEN}`, async () => {
                        await withSigner(
                            this.squeethVaultGovernance.address,
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(this.nft, [this.usdc.address])
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
                        await expect(this.subject.connect(s).controller()).to
                            .not.be.reverted;
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
                        await expect(this.subject.connect(s).router()).to.not.be
                            .reverted;
                    });
                });
            });
        });

        // describe.only("write", () => {
        //     it("", async () => {
        //         console.log(await this.subject.write());
        //     });
        // });

        describe("#takeShort", () => {
            it("mints wPowerPerp using entire weth supply as a collateral", async () => {
                let wethBalance = await this.weth.balanceOf(this.subject.address);
                expect((await this.subject.totalCollateral()).eq(0)).to.be.true;
                expect((await this.subject.wPowerPerpDebt()).eq(0)).to.be.true;
                expect(wethBalance.gt(0)).to.be.true;
                expect(
                    (await this.squeeth.balanceOf(this.subject.address)).eq(0)
                ).to.be.true;

                await this.subject.takeShort(this.healthFactor);
                let mintedSqueeth = await this.squeeth.balanceOf(this.subject.address);
                expect((await this.subject.shortVaultId()).gt(0)).to.be.true;
                expect((await this.subject.totalCollateral()).eq(wethBalance)).to.be.true;
                expect((await this.subject.wPowerPerpDebt()).eq(mintedSqueeth)).to.be.true;
                expect(mintedSqueeth.gt(0)).to.be.true;
                expect(
                    (await this.weth.balanceOf(this.subject.address)).eq(0)).to.be.true;
            });

            it("emits ShortTaken event", async () => {
                await expect(
                    this.subject.takeShort(
                        this.healthFactor
                    )
                ).to.emit(this.subject, "ShortTaken");
            });

            describe("access control:", () => {
                it("allowed: vault owner", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .takeShort(
                                this.healthFactor
                            )
                    ).to.not.be.reverted;
                });

                it("allowed: approved account", async () => {
                    let account = randomAddress();
                    await this.vaultRegistry
                        .connect(this.deployer)
                        .approve(account, this.squeethVaultNft);
                    await withSigner(account, async (s) => {
                        expect(
                            await this.subject
                                .connect(s)
                                .takeShort(
                                    this.healthFactor
                                )
                        ).to.not.be.reverted;
                    });
                });

                it("denied: any other address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .takeShort(
                                    this.healthFactor
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });

            describe("edge cases:", () => {
                describe("when short is taken twice", () => {
                    it(`reverts with ${Exceptions.INVALID_STATE}`, async () => {
                        await this.subject.takeShort(this.healthFactor);
                        await expect(this.subject.takeShort(this.healthFactor)).to.be.revertedWith(Exceptions.INVALID_STATE);;
                    });
                });
            });
        });


        describe("#closeShort", () => {
            it("closes position using oSQTH left on vault", async () => {
                await this.subject.takeShort(this.healthFactor);

                let squeethBalance = await this.squeeth.balanceOf(this.subject.address);
                expect((await this.subject.wPowerPerpDebt()).eq(squeethBalance)).to.be.true;
                
                await this.subject.closeShort();

                expect((await this.subject.shortVaultId()).eq(0)).to.be.true;
                expect((await this.subject.totalCollateral()).eq(0)).to.be.true;
                expect((await this.subject.wPowerPerpDebt()).eq(0)).to.be.true;
                expect(
                    (await this.squeeth.balanceOf(this.subject.address)).eq(0)).to.be.true;
                expect(
                    (await this.weth.balanceOf(this.subject.address)).gt(0)).to.be.true;
            });

            it("closes position using oSQTH from flash swap", async () => {
                await this.subject.takeShort(this.healthFactor);
                let squeethBalance = await this.squeeth.balanceOf(this.subject.address)
                await withSigner(this.subject.address, async (s) => {
                    await this.squeeth
                        .connect(s)
                        .transfer(this.erc20Vault.address, squeethBalance)
                });
                expect(
                    (await this.weth.balanceOf(this.subject.address)).eq(0)
                ).to.be.true;
                expect(
                    (await this.squeeth.balanceOf(this.subject.address)).eq(0)
                ).to.be.true;

                await this.subject.closeShort();

                expect((await this.subject.wPowerPerpDebt()).eq(0)).to.be.true;
                expect((await this.subject.totalCollateral()).eq(0)).to.be.true;
                expect(
                    (await this.squeeth.balanceOf(this.subject.address)).eq(0)).to.be.true;
                expect(
                    (await this.weth.balanceOf(this.subject.address)).gt(0)).to.be.true;
            });

            it("emits ShortClosed event", async () => {
                await expect(
                    this.subject.takeShort(
                        this.healthFactor
                    ))
                await expect(
                    this.subject.closeShort()
                ).to.emit(this.subject, "ShortClosed");
            });

            describe("access control:", () => {
                it("allowed: vault owner", async () => {
                    await this.subject.takeShort(this.healthFactor);
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .closeShort()
                    ).to.not.be.reverted;
                });

                it("allowed: approved account", async () => {
                    let account = randomAddress();
                    let nft = Number(await this.vaultRegistry.vaultsCount());
                    await this.vaultRegistry
                        .connect(this.deployer)
                        .approve(account, nft);
                    await this.subject.takeShort(this.healthFactor);

                    await withSigner(account, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .closeShort()
                        ).to.not.be.reverted;
                    });
                });

                it("denied: any other address", async () => {
                    await this.subject.takeShort(this.healthFactor);
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .closeShort()
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });

            describe("edge cases:", () => {
                describe("when short is closed twice", () => {
                    it(`reverts with ${Exceptions.INVALID_STATE}`, async () => {
                        await this.subject.takeShort(this.healthFactor);
                        await this.subject.closeShort();
                        await expect(this.subject.closeShort()).to.be.revertedWith(Exceptions.INVALID_STATE);;
                    });
                });
                describe("when there is no short to close", () => {
                    it(`reverts with ${Exceptions.INVALID_STATE}`, async () => {
                        await expect(this.subject.closeShort()).to.be.revertedWith(Exceptions.INVALID_STATE);;
                    });
                });
            });
        });

        // integrationVaultBehavior.call(this, {});
    }
);
