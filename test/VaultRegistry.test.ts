import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    withSigner,
} from "./library/Helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { ProtocolGovernance, VaultRegistry } from "./types";
import { Contract } from "ethers";
import { Address } from "hardhat-deploy/dist/types";
import { REGISTER_VAULT } from "./library/PermissionIdsLibrary";
import { address, pit, RUNS } from "./library/property";
import { integer } from "fast-check";
import Exceptions from "./library/Exceptions";
import { VAULT_INTERFACE_ID } from "./library/Constants";
import { contract } from "./library/setup";

type CustomContext = {
    ownerSigner: SignerWithAddress;
    newProtocolGovernance: Contract;
    allowedRegisterVaultSigner: SignerWithAddress;
    erc165Mock: Contract;
    anotherERC165Mock: Contract;
    nft: number;
    randomNft: number;
};
type DeployOptions = {
    name?: string;
    symbol?: string;
    protocolGovernance?: ProtocolGovernance;
};

contract<VaultRegistry, DeployOptions, CustomContext>(
    "VaultRegistry",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();
                    this.ownerSigner = await addSigner(randomAddress());
                    this.allowedRegisterVaultSigner = await addSigner(
                        randomAddress()
                    );

                    await this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(
                            this.allowedRegisterVaultSigner.address,
                            [REGISTER_VAULT]
                        );
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitPermissionGrants(
                            this.allowedRegisterVaultSigner.address
                        );
                    const { address } = await deployments.deploy(
                        "VaultRegistry",
                        {
                            from: this.deployer.address,
                            contract: "VaultRegistry",
                            args: [
                                options?.name || "Test",
                                options?.symbol || "TST",
                                options?.protocolGovernance ||
                                    this.protocolGovernance.address,
                            ],
                            autoMine: true,
                        }
                    );
                    this.subject = await ethers.getContractAt(
                        "VaultRegistry",
                        address
                    );

                    const MockVaultFactory = await ethers.getContractFactory("MockERC165");
                    this.erc165Mock = await MockVaultFactory.deploy();
                    this.anotherERC165Mock = await MockVaultFactory.deploy();

                    await this.erc165Mock.allowInterfaceId(VAULT_INTERFACE_ID);
                    this.nft = Number(
                        await this.subject
                            .connect(this.allowedRegisterVaultSigner)
                            .callStatic.registerVault(
                                this.erc165Mock.address,
                                this.ownerSigner.address
                            )
                    );
                    this.subject
                        .connect(this.allowedRegisterVaultSigner)
                        .registerVault(
                            this.erc165Mock.address,
                            this.ownerSigner.address
                        );

                    this.randomNft = Math.round(Math.random() * 1000000 + 10);

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

                    this.newProtocolGovernance = await ethers.getContract(
                        "ProtocolGovernance",
                        singleton
                    );
                    console.log(this.erc165Mock.address);
                    console.log(this.anotherERC165Mock.address);
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
                    this.erc165Mock.address
                ]);
                this.subject
                    .connect(this.allowedRegisterVaultSigner)
                    .registerVault(
                        this.anotherERC165Mock.address,
                        this.ownerSigner.address
                    );
                expect(await this.subject.vaults()).to.deep.equal([
                    this.erc165Mock.address,
                    this.anotherERC165Mock.address
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
                expect(await this.subject.vaultForNft(this.nft)).to.equal(
                    this.erc165Mock.address
                );
                expect(await this.subject.vaultForNft(this.randomNft)).to.equal(
                    ethers.constants.AddressZero
                );
                await this.anotherERC165Mock.allowInterfaceId(
                    VAULT_INTERFACE_ID
                );
                this.randomNft = Number(
                    await this.subject
                        .connect(this.allowedRegisterVaultSigner)
                        .callStatic.registerVault(
                            this.anotherERC165Mock.address,
                            this.ownerSigner.address
                        )
                );
                this.subject
                    .connect(this.allowedRegisterVaultSigner)
                    .registerVault(
                        this.anotherERC165Mock.address,
                        this.ownerSigner.address
                    );
                expect(await this.subject.vaultForNft(this.randomNft)).to.equal(
                    this.anotherERC165Mock.address
                );
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject.connect(s).vaultForNft(this.nft)
                        ).to.not.be.reverted;
                    });
                });
            });

            describe("edge cases", () => {
                describe("when Vault NFT is not registered in VaultRegistry", () => {
                    it("returns zero address", async () => {
                        let randomNumber = Math.round(Math.random() * 100 + 10);
                        expect(
                            await this.subject.vaultForNft(randomNumber)
                        ).to.equal(ethers.constants.AddressZero);
                    });
                });
            });
        });

        describe("#nftForVault", () => {
            it("resolves VaultRegistry NFT by Vault address", async () => {
                expect(
                    await this.subject.nftForVault(this.erc165Mock.address)
                ).to.equal(this.nft);
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .nftForVault(this.erc165Mock.address)
                        ).to.not.be.reverted;
                    });
                });
            });

            describe("edge cases", () => {
                describe("when Vault is not registered in VaultRegistry", () => {
                    it("returns zero", async () => {
                        expect(
                            await this.subject.nftForVault(randomAddress())
                        ).to.equal(0);
                    });
                });
            });
        });

        describe("#isLocked", () => {
            it("checks if token is locked (not transferable)", async () => {
                await this.subject.connect(this.ownerSigner).lockNft(this.nft);
                expect(await this.subject.isLocked(this.nft)).to.be.true;
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(this.subject.connect(s).isLocked(this.nft))
                            .to.not.be.reverted;
                    });
                });
            });

            describe("edge cases", () => {
                describe("when VaultRegistry NFT is not registered in VaultRegistry", () => {
                    it("returns false", async () => {
                        expect(await this.subject.isLocked(this.randomNft)).to
                            .be.false;
                    });
                });
            });
        });

        describe("#protocolGovernance", () => {
            it("returns ProtocolGovernance address", async () => {
                expect(await this.subject.protocolGovernance()).to.eq(
                    this.protocolGovernance.address
                );
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(this.subject.protocolGovernance()).to.not
                            .be.reverted;
                    });
                });
            });
        });

        describe("#stagedProtocolGovernance", () => {
            it("returns ProtocolGovernance address staged for commit", async () => {
                await this.subject
                    .connect(this.admin)
                    .stageProtocolGovernance(
                        this.newProtocolGovernance.address
                    );
                expect(
                    await this.subject.stagedProtocolGovernance()
                ).to.be.equal(this.newProtocolGovernance.address);
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
                        await sleep(this.governanceDelay);
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
                    .stageProtocolGovernance(
                        this.newProtocolGovernance.address
                    );
                expect(
                    Math.abs(
                        Number(
                            await this.subject.stagedProtocolGovernanceTimestamp()
                        ) -
                            now() -
                            Number(this.governanceDelay)
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
                        await sleep(this.governanceDelay);
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
                expect(await this.subject.vaultsCount()).to.be.equal(1);
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(this.subject.connect(s).vaultsCount()).to
                            .not.be.reverted;
                    });
                });
            });

            // describe("properties", () => {
            //     pit(
            //         "@property: when N new vaults have been registered, vaults count will be increased by N",
            //         { numRuns: RUNS.verylow },
            //         integer({ min: 1, max: 5 }),
            //         async (vaultsCount: number): Promise<boolean> => {
            //             await deployments.fixture();
            //             let oldVaultsCount = Number(
            //                 await this.subject.vaultsCount()
            //             );
            //             for (var i = 0; i < vaultsCount; ++i) {
            //                 await deployments.deploy("MockERC165", {
            //                     from: this.deployer.address,
            //                     contract: "MockERC165",
            //                     args: [],
            //                     autoMine: true,
            //                 });
            //                 let newMock = await ethers.getContract(
            //                     "MockERC165"
            //                 );
            //                 await newMock.allowInterfaceId(VAULT_INTERFACE_ID);

            //                 this.subject
            //                     .connect(this.allowedRegisterVaultSigner)
            //                     .registerVault(
            //                         newMock.address,
            //                         this.ownerSigner.address
            //                     );
            //             }
            //             let newVaultsCount = Number(
            //                 await this.subject.vaultsCount()
            //             );
            //             expect(newVaultsCount - oldVaultsCount).to.be.equal(
            //                 vaultsCount
            //             );
            //             expect(
            //                 (await this.subject.vaults()).length
            //             ).to.be.equal(await this.subject.vaultsCount());
            //             return true;
            //         }
            //     );
            // });

            describe("edge cases", () => {
                describe("when new vault is registered", () => {
                    it("is increased by 1", async () => {
                        let oldVaultsCount = Number(
                            await this.subject.vaultsCount()
                        );
                        await this.anotherERC165Mock.allowInterfaceId(
                            VAULT_INTERFACE_ID
                        );
                        this.subject
                            .connect(this.allowedRegisterVaultSigner)
                            .registerVault(
                                this.anotherERC165Mock.address,
                                this.ownerSigner.address
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
                const newNft = Number(
                    await this.subject
                        .connect(this.allowedRegisterVaultSigner)
                        .callStatic.registerVault(
                            this.anotherERC165Mock.address,
                            newOwner
                        )
                );
                await this.subject
                    .connect(this.allowedRegisterVaultSigner)
                    .registerVault(this.anotherERC165Mock.address, newOwner);
                expect(await this.subject.balanceOf(newOwner)).to.be.equal(1);
                expect(await this.subject.vaultForNft(newNft)).to.be.equal(
                    this.anotherERC165Mock.address
                );
            });
            it("emits VaultRegistered event", async () => {
                await expect(
                    this.subject
                        .connect(this.allowedRegisterVaultSigner)
                        .registerVault(
                            this.anotherERC165Mock.address,
                            this.ownerSigner.address
                        )
                ).to.emit(this.subject, "VaultRegistered");
            });

            // describe("properties", () => {
            //     pit(
            //         "@property: minted NFT equals to vaultRegistry#vaultsCount",
            //         { numRuns: 1 },
            //         address.filter((x) => x != ethers.constants.AddressZero),
            //         async (address: Address): Promise<boolean> => {
            //             await deployments.fixture();
            //             const newNft = await this.subject
            //                 .connect(this.allowedRegisterVaultSigner)
            //                 .callStatic.registerVault(
            //                     this.anotherERC165Mock.address,
            //                     address
            //                 );
            //             this.subject
            //                 .connect(this.allowedRegisterVaultSigner)
            //                 .registerVault(
            //                     this.anotherERC165Mock.address,
            //                     address
            //                 );
            //             expect(
            //                 Number(await this.subject.vaultsCount())
            //             ).to.be.equal(Number(newNft));
            //             return true;
            //         }
            //     );
            // });

            describe("access control:", () => {
                it("allowed: any account with Register Vault permissions", async () => {
                    await expect(
                        this.subject
                            .connect(this.allowedRegisterVaultSigner)
                            .registerVault(
                                this.anotherERC165Mock.address,
                                this.ownerSigner.address
                            )
                    ).to.not.be.reverted;
                });
                it("denied: any other address", async () => {
                    let randomAddr = randomAddress();
                    await withSigner(randomAddr, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .registerVault(
                                    this.anotherERC165Mock.address,
                                    this.ownerSigner.address
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });

            describe("edge cases", () => {
                describe("when address doesn't conform to IVault interface (IERC165)", () => {
                    it(
                        "reverts with " + Exceptions.INVALID_INTERFACE,
                        async () => {
                            await this.anotherERC165Mock.denyInterfaceId(
                                VAULT_INTERFACE_ID
                            );
                            await expect(
                                this.subject
                                    .connect(this.allowedRegisterVaultSigner)
                                    .registerVault(
                                        this.anotherERC165Mock.address,
                                        this.ownerSigner.address
                                    )
                            ).to.be.revertedWith(Exceptions.INVALID_INTERFACE);
                        }
                    );
                });

                describe("when owner address is zero", () => {
                    it("reverts with " + Exceptions.ADDRESS_ZERO, async () => {
                        await expect(
                            this.subject
                                .connect(this.allowedRegisterVaultSigner)
                                .registerVault(
                                    this.anotherERC165Mock.address,
                                    ethers.constants.AddressZero
                                )
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });

        describe("#stageProtocolGovernance", () => {
            let stagedFixture: Function;
            before(async () => {
                stagedFixture = await deployments.createFixture(async () => {
                    await this.deploymentFixture();
                    await this.subject
                        .connect(this.admin)
                        .stageProtocolGovernance(
                            this.newProtocolGovernance.address
                        );
                });
            });
            beforeEach(async () => {
                await stagedFixture();
            });
            it("stages new ProtocolGovernance for commit", async () => {
                expect(
                    await this.subject.stagedProtocolGovernance()
                ).to.be.equal(this.newProtocolGovernance.address);
            });
            it("sets the stagedProtocolGovernanceTimestamp after which #commitStagedProtocolGovernance can be called", async () => {
                expect(
                    Number(
                        await this.subject.stagedProtocolGovernanceTimestamp()
                    ) -
                        now() -
                        Number(this.governanceDelay)
                ).to.be.lessThanOrEqual(5);
            });

            describe("access control:", () => {
                it("allowed: ProtocolGovernance Admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageProtocolGovernance(
                                this.newProtocolGovernance.address
                            )
                    ).to.not.be.reverted;
                });
                it("denied: any other address", async () => {
                    let randomAddr = randomAddress();
                    await withSigner(randomAddr, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .stageProtocolGovernance(
                                    this.newProtocolGovernance.address
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .stageProtocolGovernance(
                                this.newProtocolGovernance.address
                            )
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });

            describe("edge cases", () => {
                describe("when new ProtocolGovernance is a zero address", () => {
                    it("reverts with " + Exceptions.ADDRESS_ZERO, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageProtocolGovernance(
                                    ethers.constants.AddressZero
                                )
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });

        describe("#commitStagedProtocolGovernance", () => {
            let stagedFixture: Function;
            before(async () => {
                stagedFixture = await deployments.createFixture(async () => {
                    await this.deploymentFixture();
                    await this.subject
                        .connect(this.admin)
                        .stageProtocolGovernance(
                            this.newProtocolGovernance.address
                        );
                });
            });
            beforeEach(async () => {
                await stagedFixture();
                await sleep(this.governanceDelay);
            });
            it("commits staged ProtocolGovernance", async () => {
                expect(await this.subject.protocolGovernance()).to.be.equal(
                    this.protocolGovernance.address
                );
                await this.subject
                    .connect(this.admin)
                    .commitStagedProtocolGovernance();
                expect(await this.subject.protocolGovernance()).to.be.equal(
                    this.newProtocolGovernance.address
                );
            });
            it("resets staged ProtocolGovernanceTimestamp", async () => {
                expect(
                    await this.subject.stagedProtocolGovernanceTimestamp()
                ).to.not.be.equal(0);
                await this.subject
                    .connect(this.admin)
                    .commitStagedProtocolGovernance();
                expect(
                    await this.subject.stagedProtocolGovernanceTimestamp()
                ).to.be.equal(0);
            });
            it("resets staged ProtocolGovernance", async () => {
                expect(
                    await this.subject.stagedProtocolGovernance()
                ).to.not.be.equal(ethers.constants.AddressZero);
                await this.subject
                    .connect(this.admin)
                    .commitStagedProtocolGovernance();
                expect(
                    await this.subject.stagedProtocolGovernance()
                ).to.be.equal(ethers.constants.AddressZero);
            });

            describe("access control:", () => {
                it("allowed: ProtocolGovernance Admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .commitStagedProtocolGovernance()
                    ).to.not.be.reverted;
                });
                it("denied: any other address", async () => {
                    let randomAddr = randomAddress();
                    await withSigner(randomAddr, async (s) => {
                        await expect(
                            this.subject.commitStagedProtocolGovernance()
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });

            describe("edge cases", () => {
                describe("when nothing staged", () => {
                    it("reverts with " + Exceptions.INIT, async () => {
                        await this.subject
                            .connect(this.admin)
                            .commitStagedProtocolGovernance();
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitStagedProtocolGovernance()
                        ).to.be.revertedWith(Exceptions.INIT);
                    });
                });

                describe("when called before stagedProtocolGovernanceTimestamp", () => {
                    it("reverts with " + Exceptions.TIMESTAMP, async () => {
                        await this.subject
                            .connect(this.admin)
                            .stageProtocolGovernance(
                                this.newProtocolGovernance.address
                            );
                        await sleep(this.governanceDelay / 2);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitStagedProtocolGovernance()
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    });

                    it("reverts with " + Exceptions.TIMESTAMP, async () => {
                        await this.subject
                            .connect(this.admin)
                            .stageProtocolGovernance(
                                this.newProtocolGovernance.address
                            );
                        await sleep(this.governanceDelay - 5);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .commitStagedProtocolGovernance()
                        ).to.be.revertedWith(Exceptions.TIMESTAMP);
                    });
                });
            });
        });

        describe("#adminApprove", () => {
            it("approves token to new address", async () => {
                let randomAddr = randomAddress();
                await this.subject
                    .connect(this.admin)
                    .adminApprove(randomAddr, this.nft);
                expect(await this.subject.getApproved(this.nft)).to.be.equal(
                    randomAddr
                );
            });

            describe("access control:", () => {
                it("allowed: ProtocolGovernance Admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .adminApprove(this.ownerSigner.address, this.nft)
                    ).to.not.be.reverted;
                });
                it("denied: any other address", async () => {
                    let randomAddr = randomAddress();
                    await withSigner(randomAddr, async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .adminApprove(
                                    this.ownerSigner.address,
                                    this.nft
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .adminApprove(this.ownerSigner.address, this.nft)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
            describe("edge cases", () => {
                describe("when NFT doesn't exist", () => {
                    it(
                        "reverts with " + Exceptions.UNEXISTING_TOKEN,
                        async () => {
                            await expect(
                                this.subject
                                    .connect(this.admin)
                                    .adminApprove(
                                        this.ownerSigner.address,
                                        this.randomNft
                                    )
                            ).to.be.revertedWith(Exceptions.UNEXISTING_TOKEN);
                        }
                    );
                });
            });
        });

        describe("#lockNft", () => {
            let randomNft = Math.round(Math.random() * 100 + 10);

            it("locks NFT (disables any transfer)", async () => {
                expect(await this.subject.isLocked(randomNft)).to.be.false;
                expect(await this.subject.isLocked(this.nft)).to.be.false;
                await this.subject.connect(this.ownerSigner).lockNft(this.nft);
                expect(await this.subject.isLocked(this.nft)).to.be.true;
                await expect(
                    this.subject
                        .connect(this.ownerSigner)
                        .transferFrom(
                            this.ownerSigner.address,
                            randomAddress(),
                            this.nft
                        )
                ).to.be.revertedWith(Exceptions.LOCK);
            });

            it("emits TokenLocked event", async () => {
                await expect(
                    this.subject.connect(this.ownerSigner).lockNft(this.nft)
                ).to.emit(this.subject, "TokenLocked");
            });

            describe("access control:", () => {
                it("allowed: NFT owner", async () => {
                    await expect(
                        this.subject.connect(this.ownerSigner).lockNft(this.nft)
                    ).to.not.be.reverted;
                });
                it("denied: any other address", async () => {
                    let randomAddr = randomAddress();
                    await withSigner(randomAddr, async (s) => {
                        await expect(
                            this.subject.connect(s).lockNft(this.nft)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
                it("denied: protocol admin", async () => {
                    await expect(
                        this.subject.connect(this.admin).lockNft(this.nft)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });

            describe("edge cases", () => {
                describe("when NFT has already been locked", () => {
                    it("succeeds", async () => {
                        await this.subject
                            .connect(this.ownerSigner)
                            .lockNft(this.nft);
                        expect(await this.subject.isLocked(this.nft)).to.be
                            .true;
                        await expect(
                            this.subject
                                .connect(this.ownerSigner)
                                .lockNft(this.nft)
                        ).to.not.be.reverted;
                        expect(await this.subject.isLocked(this.nft)).to.be
                            .true;
                        await expect(
                            this.subject
                                .connect(this.ownerSigner)
                                .transferFrom(
                                    this.ownerSigner.address,
                                    randomAddress(),
                                    this.nft
                                )
                        ).to.be.revertedWith(Exceptions.LOCK);
                    });
                });
            });
        });
    }
);
