import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    withSigner,
} from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import { setupDefaultContext, TestContext } from "./library/setup";
import { address, pit } from "./library/property";
import { Arbitrary } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import { InternalParamsStructOutput } from "./types/IVaultGovernance";
import { ProtocolGovernance, VaultRegistry } from "./types";
import { Contract } from "ethers";
import { BigNumber } from "@ethersproject/bignumber";
import { randomBytes } from "crypto";

type CustomContext = {
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
    newERC20Vault: Contract;
    newAaveVault: Contract;
    anotherERC20Vault: Contract;
    nftERC20: number;
    nftAave: number;
    nftAnotherERC20: number;
    newProtocolGovernance: Contract;
};
type DeployOptions = {
    name?: string;
    symbol?: string;
    protocolGovernance?: ProtocolGovernance;
};

// @ts-ignore
describe("VaultRegistry", function (this: TestContext<
    VaultRegistry,
    DeployOptions
> &
    CustomContext) {
    before(async () => {
        // @ts-ignore
        await setupDefaultContext.call(this);
        this.deploymentFixture = deployments.createFixture(
            async (_, options?: DeployOptions) => {
                await deployments.fixture();

                const { address } = await deployments.deploy("VaultRegistry", {
                    from: this.deployer.address,
                    contract: "VaultRegistry",
                    args: [
                        options?.name || "Test",
                        options?.symbol || "TST",
                        options?.protocolGovernance ||
                            this.protocolGovernance.address,
                    ],
                    autoMine: true,
                });
                this.subject = await ethers.getContractAt(
                    "VaultRegistry",
                    address
                );
                this.ownerSigner = await addSigner(randomAddress());
                this.strategySigner = await addSigner(randomAddress());

                // register new ERC20Vault
                await this.erc20VaultGovernance.createVault(
                    [this.usdc.address],
                    this.ownerSigner.address
                );
                this.newERC20Vault = await ethers.getContract("ERC20Vault");
                await withSigner(
                    this.erc20VaultGovernance.address,
                    async (s) => {
                        await this.subject
                            .connect(s)
                            .registerVault(
                                this.newERC20Vault.address,
                                await this.ownerSigner.getAddress()
                            );
                    }
                );
                this.nftERC20 = (await this.subject.vaultsCount()).toNumber();

                // register new AaveVault
                await this.aaveVaultGovernance.createVault(
                    [this.weth.address],
                    this.ownerSigner.address
                );
                this.newAaveVault = await ethers.getContract("AaveVault");
                await withSigner(
                    this.aaveVaultGovernance.address,
                    async (s) => {
                        await this.subject
                            .connect(s)
                            .registerVault(
                                this.newAaveVault.address,
                                await this.ownerSigner.getAddress()
                            );
                    }
                );
                this.nftAave = (await this.subject.vaultsCount()).toNumber();

                // create another ERC20Vault
                await this.erc20VaultGovernance.createVault(
                    [this.usdc.address],
                    this.ownerSigner.address
                );
                this.anotherERC20Vault = await ethers.getContract("ERC20Vault");
                this.nftAnotherERC20 = this.nftAave + 1;

                // deploy new ProtocolGovernance
                const { address: singleton } = await deployments.deploy(
                    "ProtocolGovernance",
                    {
                        from: this.deployer.address,
                        args: [this.deployer.address],
                        log: true,
                        autoMine: true,
                    }
                );

                this.newProtocolGovernance = await ethers.getContractAt(
                    "ProtocolGovernance",
                    singleton
                );
                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
        this.startTimestamp = now();
        await sleepTo(this.startTimestamp);
    });

    describe("#constructor", () => {
        it("creates VaultRegistry", async () => {
            expect(ethers.constants.AddressZero).to.not.eq(
                this.subject.address
            );
        });
        it("initializes ProtocolGovernance address", async () => {
            expect(await this.subject.protocolGovernance()).to.be.equal(
                this.protocolGovernance.address
            );
        });
        it("initializes ERC721 token name", async () => {
            expect(await this.subject.name()).to.be.equal("Test");
        });
        it("initializes ERC721 token symbol", async () => {
            expect(await this.subject.symbol()).to.be.equal("TST");
        });
    });

    describe("#vaults", () => {
        it("returns all registered vaults", async () => {
            expect(await this.subject.vaults()).to.deep.equal([
                this.newERC20Vault.address,
                this.newAaveVault.address,
            ]);
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(this.subject.connect(s).vaults()).to.not.be
                        .reverted;
                });
            });
        });
    });

    describe("#vaultForNft", () => {
        it("resolves Vault address by VaultRegistry NFT", async () => {
            expect(await this.subject.vaultForNft(this.nftERC20)).to.equal(
                this.newERC20Vault.address
            );
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).vaultForNft(this.nftAave)
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when Vault NFT is not registered in VaultRegistry", () => {
                it("returns zero address", async () => {
                    expect(
                        await this.subject.vaultForNft(this.nftAnotherERC20)
                    ).to.equal(ethers.constants.AddressZero);
                });
            });
        });
    });

    describe("#nftForVault", () => {
        it("resolves VaultRegistry NFT by Vault address", async () => {
            expect(
                await this.subject.nftForVault(this.newERC20Vault.address)
            ).to.equal(this.nftERC20);
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .nftForVault(this.newERC20Vault.address)
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when Vault is not registered in VaultRegistry", () => {
                it("returns zero", async () => {
                    expect(
                        await this.subject.nftForVault(
                            this.protocolGovernance.address
                        )
                    ).to.equal(0);
                });
            });
        });
    });

    describe("#isLocked", () => {
        it("checks if token is locked (not transferable)", async () => {
            await this.subject.connect(this.ownerSigner).lockNft(this.nftERC20);
            expect(await this.subject.isLocked(this.nftERC20)).to.be.equal(
                true
            );
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).isLocked(this.nftERC20)
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when VaultRegistry NFT is not registered in VaultRegistry", () => {
                it("returns false", async () => {
                    expect(
                        await this.subject.isLocked(this.nftAnotherERC20)
                    ).to.be.equal(false);
                });
            });
        });
    });

    describe("#protocolGovernance", () => {
        it("returns ProtocolGovernance address", async () => {
            expect(await this.subject.protocolGovernance()).to.be.equal(
                this.protocolGovernance.address
            );
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(this.subject.protocolGovernance()).to.not.be
                        .reverted;
                });
            });
        });
    });

    describe("#stagedProtocolGovernance", () => {
        it("returns ProtocolGovernance address staged for commit", async () => {
            await this.subject
                .connect(this.admin)
                .stageProtocolGovernance(this.newProtocolGovernance.address);
            expect(await this.subject.stagedProtocolGovernance()).to.be.equal(
                this.newProtocolGovernance.address
            );
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).stagedProtocolGovernance()
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when nothing staged", () => {
                it("returns zero address", async () => {
                    expect(
                        await this.subject.stagedProtocolGovernance()
                    ).to.be.equal(ethers.constants.AddressZero);
                });
            });

            describe("right after #commitStagedProtocolGovernance was called", () => {
                it("returns zero address", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageProtocolGovernance(
                            this.newProtocolGovernance.address
                        );
                    await sleep(
                        Number(await this.protocolGovernance.governanceDelay())
                    );
                    await this.subject
                        .connect(this.admin)
                        .commitStagedProtocolGovernance();
                    expect(
                        await this.subject.stagedProtocolGovernance()
                    ).to.be.equal(ethers.constants.AddressZero);
                });
            });
        });
    });

    describe("#stagedProtocolGovernanceTimestamp", () => {
        it("returns timestamp after which #commitStagedProtocolGovernance can be called", async () => {
            await this.subject
                .connect(this.admin)
                .stageProtocolGovernance(this.newProtocolGovernance.address);
            expect(
                Math.abs(
                    Number(
                        await this.subject.stagedProtocolGovernanceTimestamp()
                    ) -
                        now() -
                        Number(await this.protocolGovernance.governanceDelay())
                )
            ).to.be.lessThanOrEqual(1);
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.stagedProtocolGovernanceTimestamp()
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when nothing is staged", () => {
                it("returns 0", async () => {
                    expect(
                        await this.subject.stagedProtocolGovernanceTimestamp()
                    ).to.be.equal(0);
                });
            });
            describe("right after #commitStagedProtocolGovernance was called", () => {
                it("returns 0", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageProtocolGovernance(
                            this.newProtocolGovernance.address
                        );
                    await sleep(
                        Number(await this.protocolGovernance.governanceDelay())
                    );
                    await this.subject
                        .connect(this.admin)
                        .commitStagedProtocolGovernance();
                    expect(
                        await this.subject.stagedProtocolGovernanceTimestamp()
                    ).to.be.equal(0);
                });
            });
        });
    });

    describe("#vaultsCount", () => {
        it("returns the number of registered vaults", async () => {
            expect(await this.subject.vaultsCount()).to.be.equal(2);
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(this.subject.vaultsCount()).to.not.be.reverted;
                });
            });
        });
        describe("edge cases", () => {
            describe("when new vault is registered", () => {
                it("is increased by 1", async () => {
                    let oldVaultsCount = Number(
                        await this.subject.vaultsCount()
                    );
                    await withSigner(
                        this.erc20VaultGovernance.address,
                        async (s) => {
                            await this.subject
                                .connect(s)
                                .registerVault(
                                    this.anotherERC20Vault.address,
                                    await this.ownerSigner.getAddress()
                                );
                        }
                    );
                    this.nftAnotherERC20 = Number(
                        await this.subject.vaultsCount()
                    );
                    let newVaultsCount = Number(
                        await this.subject.vaultsCount()
                    );
                    expect(newVaultsCount - oldVaultsCount).to.be.equal(1);
                });
            });
        });
    });

    describe("#registerVault", () => {
        it("binds minted ERC721 NFT to Vault address and transfers minted NFT to owner specified in args", async () => {
            let newOwner = randomAddress();
            expect(await this.subject.balanceOf(newOwner)).to.be.equal(0);
            await withSigner(this.erc20VaultGovernance.address, async (s) => {
                await this.subject
                    .connect(s)
                    .registerVault(this.anotherERC20Vault.address, newOwner);
            });
            expect(await this.subject.balanceOf(newOwner)).to.be.equal(1);
        });
        it("emits VaultRegistered event", async () => {
            await withSigner(this.erc20VaultGovernance.address, async (s) => {
                await expect(
                    this.subject
                        .connect(s)
                        .registerVault(
                            this.anotherERC20Vault.address,
                            this.ownerSigner.address
                        )
                ).to.emit(this.subject, "VaultRegistered");
            });
        });

        describe("properties", () => {
            it("@property: minted NFT equals to vaultRegistry#vaultsCount", async () => {
                let newOwner = randomAddress();
                expect(await this.subject.balanceOf(newOwner)).to.be.equal(0);
                await withSigner(
                    this.erc20VaultGovernance.address,
                    async (s) => {
                        await this.subject
                            .connect(s)
                            .registerVault(
                                this.anotherERC20Vault.address,
                                newOwner
                            );
                    }
                );
                expect(await this.subject.balanceOf(newOwner)).to.be.equal(1);
                expect(
                    await this.subject.ownerOf(
                        (await this.subject.vaultsCount()).toNumber()
                    )
                ).to.be.equal(newOwner);
            });
        });

        describe("access control:", () => {
            it("allowed: any VaultGovernance registered in ProtocolGovernance", async () => {
                await withSigner(
                    this.erc20VaultGovernance.address,
                    async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .registerVault(
                                    this.anotherERC20Vault.address,
                                    this.ownerSigner.address
                                )
                        ).to.not.be.reverted;
                    }
                );
            });
            it("denied: any other address", async () => {
                let randomAddr = randomAddress();
                while (
                    randomAddr == this.erc20VaultGovernance.address ||
                    randomAddr == this.aaveVaultGovernance.address ||
                    randomAddr == this.uniV3VaultGovernance.address
                ) {
                    randomAddr = randomAddress();
                }
                await withSigner(randomAddr, async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .registerVault(
                                this.anotherERC20Vault.address,
                                this.ownerSigner.address
                            )
                    ).to.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            // FIX Vault Registry Contract
            xdescribe("when address doesn't conform to IVault interface (IERC165)", () => {
                it("reverts", async () => {});
            });

            describe("when owner address is zero", () => {
                it("reverts", async () => {
                    await withSigner(
                        this.erc20VaultGovernance.address,
                        async (s) => {
                            await expect(
                                this.subject
                                    .connect(s)
                                    .registerVault(
                                        this.anotherERC20Vault.address,
                                        ethers.constants.AddressZero
                                    )
                            ).to.be.reverted;
                        }
                    );
                });
            });
        });
    });

    describe("#stageProtocolGovernance", () => {
        it("stages new ProtocolGovernance for commit", async () => {
            await this.subject
                .connect(this.admin)
                .stageProtocolGovernance(this.newProtocolGovernance.address);

            expect(await this.subject.stagedProtocolGovernance()).to.be.equal(
                this.newProtocolGovernance.address
            );
        });
        it("sets the stagedProtocolGovernanceTimestamp after which #commitStagedProtocolGovernance can be called", async () => {
            await this.subject
                .connect(this.admin)
                .stageProtocolGovernance(this.newProtocolGovernance.address);

            expect(
                Number(await this.subject.stagedProtocolGovernanceTimestamp()) -
                    now() -
                    Number(await this.protocolGovernance.governanceDelay())
            ).to.be.lessThanOrEqual(1);
        });

        describe("access control:", () => {
            it("allowed: ProtocolGovernance Admin", async () => {
                await this.subject
                    .connect(this.admin)
                    .stageProtocolGovernance(
                        this.newProtocolGovernance.address
                    );
            });
            it("denied: any other address", async () => {
                let randomAddr = randomAddress();
                while (randomAddr == this.admin.address) {
                    randomAddr = randomAddress();
                }
                await withSigner(randomAddr, async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .stageProtocolGovernance(
                                this.newProtocolGovernance.address
                            )
                    ).to.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when new ProtocolGovernance is a zero address", () => {
                it("does not fail", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageProtocolGovernance(
                                ethers.constants.AddressZero
                            )
                    ).to.not.be.reverted;
                });
            });
        });
    });

    describe("#commitStagedProtocolGovernance", () => {
        it("commits staged ProtocolGovernance resets staged ProtocolGovernance and ProtocolGovernanceTimestamp", async () => {
            await this.subject
                .connect(this.admin)
                .stageProtocolGovernance(this.newProtocolGovernance.address);
            await sleep(
                Number(await this.protocolGovernance.governanceDelay())
            );
            await this.subject
                .connect(this.admin)
                .commitStagedProtocolGovernance();
            expect(
                await this.subject.stagedProtocolGovernanceTimestamp()
            ).to.be.equal(0);
            expect(await this.subject.stagedProtocolGovernance()).to.be.equal(
                ethers.constants.AddressZero
            );
            expect(await this.subject.protocolGovernance()).to.be.equal(
                this.newProtocolGovernance.address
            );
        });

        describe("access control:", () => {
            it("allowed: ProtocolGovernance Admin", async () => {
                await this.subject
                    .connect(this.admin)
                    .stageProtocolGovernance(
                        this.newProtocolGovernance.address
                    );
                await sleep(
                    Number(await this.protocolGovernance.governanceDelay())
                );
                await expect(
                    this.subject
                        .connect(this.admin)
                        .commitStagedProtocolGovernance()
                ).to.not.be.reverted;
            });
            it("denied: any other address", async () => {
                let randomAddr = randomAddress();
                while (randomAddr == this.admin.address) {
                    randomAddr = randomAddress();
                }
                await this.subject
                    .connect(this.admin)
                    .stageProtocolGovernance(
                        this.newProtocolGovernance.address
                    );
                await sleep(
                    Number(await this.protocolGovernance.governanceDelay())
                );
                await withSigner(randomAddr, async (s) => {
                    await expect(this.subject.commitStagedProtocolGovernance())
                        .to.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when nothing staged", () => {
                it("reverts", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitStagedProtocolGovernance()
                    ).to.be.reverted;
                });
            });

            describe("when called before stagedProtocolGovernanceTimestamp", () => {
                it("reverts", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageProtocolGovernance(
                            this.newProtocolGovernance.address
                        );
                    await sleep(
                        Number(
                            await this.protocolGovernance.governanceDelay()
                        ) / 2
                    );
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitStagedProtocolGovernance()
                    ).to.be.reverted;
                });
            });
        });
    });

    describe("#adminApprove", () => {
        it("approves token to new address", async () => {
            let randomAddr = randomAddress();
            await this.subject
                .connect(this.admin)
                .adminApprove(randomAddr, this.nftERC20);
            expect(await this.subject.getApproved(this.nftERC20)).to.be.equal(
                randomAddr
            );
        });

        describe("access control:", () => {
            it("allowed: ProtocolGovernance Admin", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .adminApprove(this.ownerSigner.address, this.nftERC20)
                ).to.not.be.reverted;
            });
            it("denied: any other address", async () => {
                let randomAddr = randomAddress();
                while (randomAddr == this.admin.address) {
                    randomAddr = randomAddress();
                }
                await withSigner(randomAddr, async (s) => {
                    await expect(
                        this.subject
                            .connect(randomAddr)
                            .adminApprove(
                                this.ownerSigner.address,
                                this.nftERC20
                            )
                    ).to.be.reverted;
                });
            });
        });
        describe("edge cases", () => {
            describe("when NFT doesn't exist", () => {
                it("reverts", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .adminApprove(
                                this.ownerSigner.address,
                                this.nftAnotherERC20
                            )
                    ).to.be.reverted;
                });
            });
        });
    });

    describe("#lockNft", () => {
        it("locks NFT (disables any transfer)", async () => {
            await this.subject.connect(this.ownerSigner).lockNft(this.nftERC20);
            expect(await this.subject.isLocked(this.nftERC20)).to.be.equal(
                true
            );
        });
        it("emits TokenLocked event", async () => {
            await expect(
                this.subject.connect(this.ownerSigner).lockNft(this.nftERC20)
            ).to.emit(this.subject, "TokenLocked");
        });

        describe("access control:", () => {
            it("allowed: NFT owner", async () => {
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .lockNft(this.nftERC20)
                ).to.not.be.reverted;
            });
            it("denied: any other address", async () => {
                let randomAddr = randomAddress();
                while (randomAddr == this.ownerSigner.address) {
                    randomAddr = randomAddress();
                }
                await withSigner(randomAddr, async (s) => {
                    await expect(this.subject.connect(s).lockNft(this.nftERC20))
                        .to.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when NFT has already been locked", () => {
                it("succeeds", async () => {
                    await this.subject
                        .connect(this.ownerSigner)
                        .lockNft(this.nftERC20);
                    expect(
                        await this.subject.isLocked(this.nftERC20)
                    ).to.be.equal(true);
                    await expect(
                        this.subject
                            .connect(this.ownerSigner)
                            .lockNft(this.nftERC20)
                    ).to.not.be.reverted;
                    expect(
                        await this.subject.isLocked(this.nftERC20)
                    ).to.be.equal(true);
                });
            });
        });
    });
});
