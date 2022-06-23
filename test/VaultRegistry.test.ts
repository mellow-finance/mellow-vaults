import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    withSigner,
    randomNft,
} from "./library/Helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { MockERC165, ProtocolGovernance, VaultRegistry } from "./types";
import { Contract } from "ethers";
import { Address } from "hardhat-deploy/dist/types";
import { REGISTER_VAULT } from "./library/PermissionIdsLibrary";
import { address, pit, RUNS } from "./library/property";
import { integer } from "fast-check";
import Exceptions from "./library/Exceptions";
import {
    VAULT_INTERFACE_ID,
    VAULT_REGISTRY_INTERFACE_ID,
} from "./library/Constants";
import { contract } from "./library/setup";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";

type CustomContext = {
    ownerSigner: SignerWithAddress;
    newProtocolGovernance: Contract;
    allowedRegisterVaultSigner: SignerWithAddress;
    vaultMock: Contract;
    anotherVaultMock: Contract;
    nft: number;
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

                    const MockVaultFactory = await ethers.getContractFactory(
                        "MockERC165"
                    );
                    this.vaultMock = await MockVaultFactory.deploy();
                    this.anotherVaultMock = await MockVaultFactory.deploy();

                    await this.vaultMock.allowInterfaceId(VAULT_INTERFACE_ID);
                    await this.anotherVaultMock.allowInterfaceId(
                        VAULT_INTERFACE_ID
                    );
                    this.nft = Number(
                        await this.subject
                            .connect(this.allowedRegisterVaultSigner)
                            .callStatic.registerVault(
                                this.vaultMock.address,
                                this.ownerSigner.address
                            )
                    );
                    this.subject
                        .connect(this.allowedRegisterVaultSigner)
                        .registerVault(
                            this.vaultMock.address,
                            this.ownerSigner.address
                        );

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
                    this.vaultMock.address,
                ]);
                await this.subject
                    .connect(this.allowedRegisterVaultSigner)
                    .registerVault(
                        this.anotherVaultMock.address,
                        this.ownerSigner.address
                    );
                expect(await this.subject.vaults()).to.deep.equal([
                    this.vaultMock.address,
                    this.anotherVaultMock.address,
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
                    this.vaultMock.address
                );
                expect(await this.subject.vaultForNft(randomNft())).to.equal(
                    ethers.constants.AddressZero
                );
                await this.anotherVaultMock.allowInterfaceId(
                    VAULT_INTERFACE_ID
                );
                let anotherNft = Number(
                    await this.subject
                        .connect(this.allowedRegisterVaultSigner)
                        .callStatic.registerVault(
                            this.anotherVaultMock.address,
                            this.ownerSigner.address
                        )
                );
                this.subject
                    .connect(this.allowedRegisterVaultSigner)
                    .registerVault(
                        this.anotherVaultMock.address,
                        this.ownerSigner.address
                    );
                expect(await this.subject.vaultForNft(anotherNft)).to.equal(
                    this.anotherVaultMock.address
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
                    await this.subject.nftForVault(this.vaultMock.address)
                ).to.equal(this.nft);
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .nftForVault(this.vaultMock.address)
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
                        expect(await this.subject.isLocked(randomNft())).to.be
                            .false;
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
                describe("when nothing is staged", () => {
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

            describe("properties", () => {
                let vaultsDeploymentFixture: Function;
                let vaults: MockERC165[] = [];
                before(async () => {
                    vaultsDeploymentFixture = deployments.createFixture(
                        async () => {
                            await this.deploymentFixture();
                            const MockVaultFactory =
                                await ethers.getContractFactory("MockERC165");
                            for (var i = 0; i < 5; ++i) {
                                let newVaultMock =
                                    (await MockVaultFactory.deploy()) as MockERC165;
                                await newVaultMock.allowInterfaceId(
                                    VAULT_INTERFACE_ID
                                );
                                vaults.push(newVaultMock);
                            }
                        }
                    );
                });
                beforeEach(async () => {
                    await vaultsDeploymentFixture();
                });

                pit(
                    "when N new vaults have been registered, vaults count will be increased by N",
                    { numRuns: RUNS.verylow },
                    integer({ min: 0, max: 5 }),
                    async (vaultsCount: number): Promise<boolean> => {
                        await vaultsDeploymentFixture();
                        let oldVaultsCount = Number(
                            await this.subject.vaultsCount()
                        );
                        for (var i = 0; i < vaultsCount; ++i) {
                            await this.subject
                                .connect(this.allowedRegisterVaultSigner)
                                .registerVault(
                                    vaults[i].address,
                                    this.ownerSigner.address
                                );
                        }

                        let newVaultsCount = Number(
                            await this.subject.vaultsCount()
                        );
                        expect(newVaultsCount - oldVaultsCount).to.be.equal(
                            vaultsCount
                        );
                        expect(
                            (await this.subject.vaults()).length
                        ).to.be.equal(await this.subject.vaultsCount());
                        expect(
                            (await this.subject.vaults()).length + 1
                        ).to.not.be.equal(await this.subject.vaultsCount());
                        return true;
                    }
                );
            });
        });

        describe("#supportsInterface", () => {
            it("returns true if this contract supports a certain interface", async () => {
                expect(
                    await this.subject.supportsInterface(
                        VAULT_REGISTRY_INTERFACE_ID
                    )
                ).to.be.true;
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .supportsInterface(VAULT_REGISTRY_INTERFACE_ID)
                        ).to.not.be.reverted;
                    });
                });
            });

            describe("edge cases:", () => {
                describe("when contract does not support the given interface", () => {
                    it("returns false", async () => {
                        expect(
                            await this.subject.supportsInterface(
                                VAULT_INTERFACE_ID
                            )
                        ).to.be.false;
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
                            this.anotherVaultMock.address,
                            newOwner
                        )
                );
                await this.subject
                    .connect(this.allowedRegisterVaultSigner)
                    .registerVault(this.anotherVaultMock.address, newOwner);
                expect(await this.subject.balanceOf(newOwner)).to.be.equal(1);
                expect(await this.subject.vaultForNft(newNft)).to.be.equal(
                    this.anotherVaultMock.address
                );
            });
            it("emits VaultRegistered event", async () => {
                await expect(
                    this.subject
                        .connect(this.allowedRegisterVaultSigner)
                        .registerVault(
                            this.anotherVaultMock.address,
                            this.ownerSigner.address
                        )
                ).to.emit(this.subject, "VaultRegistered");
            });

            describe("properties", () => {
                let vaultDeploymentFixture: Function;
                let vault: MockERC165;
                before(async () => {
                    vaultDeploymentFixture = deployments.createFixture(
                        async () => {
                            await this.deploymentFixture();
                            const MockVaultFactory =
                                await ethers.getContractFactory("MockERC165");
                            vault =
                                (await MockVaultFactory.deploy()) as MockERC165;
                            await vault.allowInterfaceId(VAULT_INTERFACE_ID);
                        }
                    );
                });
                beforeEach(async () => {
                    await vaultDeploymentFixture();
                });
                pit(
                    "minted NFT equals to vaultRegistry#vaultsCount",
                    { numRuns: RUNS.mid },
                    address.filter((x) => x != ethers.constants.AddressZero),
                    async (address: Address): Promise<boolean> => {
                        await vaultDeploymentFixture();
                        const newNft = await this.subject
                            .connect(this.allowedRegisterVaultSigner)
                            .callStatic.registerVault(vault.address, address);
                        await this.subject
                            .connect(this.allowedRegisterVaultSigner)
                            .registerVault(vault.address, address);
                        expect(
                            Number(await this.subject.vaultsCount())
                        ).to.be.equal(Number(newNft));
                        return true;
                    }
                );
            });

            describe("access control:", () => {
                it("allowed: any account with Register Vault permissions", async () => {
                    await expect(
                        this.subject
                            .connect(this.allowedRegisterVaultSigner)
                            .registerVault(
                                this.anotherVaultMock.address,
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
                                    this.anotherVaultMock.address,
                                    this.ownerSigner.address
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
                it("denied: protocol governance admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .registerVault(
                                this.anotherVaultMock.address,
                                this.ownerSigner.address
                            )
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });

            describe("edge cases", () => {
                describe("when address doesn't conform to IVault interface (IERC165)", () => {
                    it(`reverts with ${Exceptions.INVALID_INTERFACE}`, async () => {
                        await this.anotherVaultMock.denyInterfaceId(
                            VAULT_INTERFACE_ID
                        );
                        await expect(
                            this.subject
                                .connect(this.allowedRegisterVaultSigner)
                                .registerVault(
                                    this.anotherVaultMock.address,
                                    this.ownerSigner.address
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_INTERFACE);
                    });
                });

                describe("when vault has already been registered", () => {
                    it(`reverts with ${Exceptions.DUPLICATE}`, async () => {
                        await this.subject
                            .connect(this.allowedRegisterVaultSigner)
                            .registerVault(
                                this.anotherVaultMock.address,
                                this.ownerSigner.address
                            );
                        await expect(
                            this.subject
                                .connect(this.allowedRegisterVaultSigner)
                                .registerVault(
                                    this.anotherVaultMock.address,
                                    this.ownerSigner.address
                                )
                        ).to.be.revertedWith(Exceptions.DUPLICATE);
                    });
                });

                describe("when owner address is zero", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.allowedRegisterVaultSigner)
                                .registerVault(
                                    this.anotherVaultMock.address,
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
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
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
                describe("when nothing is staged", () => {
                    it(`reverts with ${Exceptions.INIT}`, async () => {
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
                    it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
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

                    it(`reverts with ${Exceptions.TIMESTAMP}`, async () => {
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

        describe("#lockNft", () => {
            it("locks NFT (disables any transfer)", async () => {
                expect(await this.subject.isLocked(randomNft())).to.be.false;
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

        ContractMetaBehaviour.call(this, {
            contractName: "VaultRegistry",
            contractVersion: "1.0.0",
        });
    }
);
