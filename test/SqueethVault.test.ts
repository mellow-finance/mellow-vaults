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

        //integrationVaultBehavior.call(this, {});
    }
);
