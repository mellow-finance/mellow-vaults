import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Signer } from "ethers";
import Exceptions from "./library/Exceptions";
import {
    deploySubVaultSystem,
    deployERC20Tokens,
    deployProtocolGovernance,
} from "./library/Deployments";
import {
    ERC20,
    ERC20Vault,
    ProtocolGovernance,
    VaultRegistry,
    VaultFactory,
    VaultGovernance,
} from "./library/Types";
import { sortContractsByAddresses } from "./library/Helpers";
import { now, sleep, sleepTo } from "./library/Helpers";

describe("VaultRegistry", () => {
    let vaultRegistry: VaultRegistry;
    let vaultFactory: VaultFactory;
    let anotherVaultFactory: VaultFactory;
    let vaultGovernance: VaultGovernance;
    let anotherVaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vault: ERC20Vault;
    let anotherVault: ERC20Vault;
    let tokens: ERC20[];
    let deployer: Signer;
    let vaultOwner: Signer;
    let protocolAdmin: Signer;
    let treasury: Signer;
    let stranger: Signer;
    let nft: number;
    let anotherNft: number;
    let deployment: Function;

    before(async () => {
        [deployer, treasury, stranger, protocolAdmin] =
            await ethers.getSigners();

        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            return await deploySubVaultSystem({
                tokensCount: 2,
                adminSigner: deployer,
                vaultOwner: await deployer.getAddress(),
                treasury: await treasury.getAddress(),
                vaultType: "ERC20Vault",
            });
        });
    });

    beforeEach(async () => {
        ({
            vaultRegistry,
            vaultFactory,
            protocolGovernance,
            vaultGovernance,
            tokens,
            vault,
            anotherVault,
            nft,
            anotherNft,
        } = await deployment());
    });

    describe("constructor", () => {
        it("creates VaultRegistry", async () => {
            expect(
                await deployer.provider?.getCode(vaultRegistry.address)
            ).not.to.be.equal("0x");
        });
    });

    describe("vaults", () => {
        it("returns correct vaults", async () => {
            expect(await vaultRegistry.vaults()).to.deep.equal([
                vault.address,
                anotherVault.address,
            ]);
        });
    });

    describe("vaultForNft", () => {
        it("returns correct vault for existing nft", async () => {
            expect(await vaultRegistry.vaultForNft(nft)).to.equal(
                vault.address
            );
        });

        it("returns zero nft for nonexistent vault", async () => {
            expect(await vaultRegistry.vaultForNft(nft + 1)).to.equal(
                ethers.constants.AddressZero
            );
        });
    });

    describe("nftForVault", () => {
        it("returns correct vault for nft", async () => {
            expect(await vaultRegistry.nftForVault(vault.address)).to.equal(
                nft
            );
        });

        it("returns zero address for nonexisting nft", async () => {
            expect(
                await vaultRegistry.nftForVault(vaultFactory.address)
            ).to.equal(0);
        });
    });

    describe("registerVault", () => {
        describe("when called by VaultGovernance", async () => {
            it("registers vault", async () => {
                const anotherTokens = sortContractsByAddresses(
                    await deployERC20Tokens(5)
                );
                const [newVaultAddress, _] =
                    await vaultGovernance.callStatic.deployVault(
                        anotherTokens.map((token) => token.address),
                        [],
                        await deployer.getAddress()
                    );
                await vaultGovernance.deployVault(
                    anotherTokens.map((token) => token.address),
                    [],
                    await deployer.getAddress()
                );
                expect(await vaultRegistry.vaults()).to.deep.equal([
                    vault.address,
                    anotherVault.address,
                    newVaultAddress,
                ]);
            });
        });

        describe("when called by stranger", async () => {
            it("reverts", async () => {
                await expect(
                    vaultRegistry.registerVault(
                        vaultFactory.address,
                        await stranger.getAddress()
                    )
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("protocolGovernance", () => {
        it("has correct protocolGovernance", async () => {
            expect(await vaultRegistry.protocolGovernance()).to.equal(
                protocolGovernance.address
            );
        });
    });

    describe("stagedProtocolGovernance", () => {
        describe("when nothing staged", () => {
            it("returns address zero", async () => {
                expect(await vaultRegistry.stagedProtocolGovernance()).to.equal(
                    ethers.constants.AddressZero
                );
            });
        });

        describe("when staged new protocolGovernance", () => {
            it("returns correct stagedProtocolGovernance", async () => {
                const newProtocolGovernance = await deployProtocolGovernance({
                    adminSigner: deployer,
                });
                await vaultRegistry.stageProtocolGovernance(
                    newProtocolGovernance.address
                );
                expect(await vaultRegistry.stagedProtocolGovernance()).to.equal(
                    newProtocolGovernance.address
                );
            });
        });
    });

    describe("stagedProtocolGovernanceTimestamp", () => {
        it("returns 0 when nothing is staged", async () => {
            expect(
                await vaultRegistry.stagedProtocolGovernanceTimestamp()
            ).to.equal(0);
        });

        it("returns correct timestamp when new ProtocolGovernance is staged", async () => {
            let ts = now();
            const newProtocolGovernance = await deployProtocolGovernance({
                adminSigner: deployer,
            });
            ts += 10 ** 4;
            await sleepTo(ts);
            await vaultRegistry.stageProtocolGovernance(
                newProtocolGovernance.address
            );
            expect(
                await vaultRegistry.stagedProtocolGovernanceTimestamp()
            ).to.equal(
                ts + Number(await protocolGovernance.governanceDelay()) + 1
            );
        });
    });

    describe("vaultsCount", () => {
        it("returns correct vaults count", async () => {
            expect(await vaultRegistry.vaultsCount()).to.equal(2);
        });
    });

    describe("stageProtocolGovernance", () => {
        describe("when called by stranger", () => {
            it("reverts", async () => {
                await expect(
                    vaultRegistry
                        .connect(stranger)
                        .stageProtocolGovernance(protocolGovernance.address)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("commitStagedProtocolGovernance", () => {
        let newProtocolGovernance: ProtocolGovernance;

        beforeEach(async () => {
            newProtocolGovernance = await deployProtocolGovernance({
                adminSigner: deployer,
            });
        });

        describe("when nothing staged", () => {
            it("reverts", async () => {
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await expect(
                    vaultRegistry.commitStagedProtocolGovernance()
                ).to.be.revertedWith(Exceptions.NULL_OR_NOT_INITIALIZED);
            });
        });

        describe("when called by stranger", () => {
            it("reverts", async () => {
                await vaultRegistry.stageProtocolGovernance(
                    newProtocolGovernance.address
                );
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await expect(
                    vaultRegistry
                        .connect(stranger)
                        .commitStagedProtocolGovernance()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when called too early", () => {
            it("reverts", async () => {
                await vaultRegistry.stageProtocolGovernance(
                    protocolGovernance.address
                );
                await expect(
                    vaultRegistry.commitStagedProtocolGovernance()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });

        it("commits staged ProtocolGovernance", async () => {
            await vaultRegistry.stageProtocolGovernance(
                newProtocolGovernance.address
            );
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await vaultRegistry.commitStagedProtocolGovernance();
            expect(await vaultRegistry.protocolGovernance()).to.equal(
                newProtocolGovernance.address
            );
        });
    });
});
