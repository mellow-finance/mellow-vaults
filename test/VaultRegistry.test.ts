import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Signer } from "ethers";
import Exceptions from "./library/Exceptions";
import {
    deployERC20VaultSystem,
    deployERC20Tokens,
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
import { ProtocolGovernance_Params } from "./library/Types";
import { BigNumber } from "@ethersproject/bignumber";
import { now, sleep, sleepTo, toObject } from "./library/Helpers";

describe("VaultRegistry", () => {
    let vaultRegistry: VaultRegistry;
    let vaultFactory: VaultFactory;
    let vaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vault: ERC20Vault;
    let tokens: ERC20[];
    let deployer: Signer;
    let vaultOwner: Signer;
    let protocolAdmin: Signer;
    let treasury: Signer;
    let stranger: Signer;
    let nft: number;
    let deployment: Function;

    before(async () => {
        [deployer, treasury, stranger] = await ethers.getSigners();

        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            return await deployERC20VaultSystem({
                tokensCount: 2,
                adminSigner: deployer,
                vaultOwner: await deployer.getAddress(),
                treasury: await treasury.getAddress(),
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
            nft,
        } = await deployment());
    });

    describe("constructor", () => {
        it("deployes", async () => {});
    });

    describe("vaults", () => {
        it("has correct vaults", async () => {
            expect(await vaultRegistry.vaults()).to.deep.equal([vault.address]);
        });
    });

    describe("vaultForNft", () => {
        it("has correct vault for existent nft", async () => {
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
        it("has correct vault for nft", async () => {
            expect(await vaultRegistry.nftForVault(vault.address)).to.equal(
                nft
            );
        });

        it("has zero address for nonexistent nft", async () => {
            expect(
                await vaultRegistry.nftForVault(vaultFactory.address)
            ).to.equal(0);
        });
    });

    describe("registerVault", () => {
        describe("when called by VaultGovernance", async () => {
            it("registers vault", async () => {
                const anotherTokens = sortContractsByAddresses(await deployERC20Tokens(5));
                const [anotherVaultAddress, anotherNft] = await vaultGovernance.callStatic.deployVault(
                    anotherTokens.map((token) => token.address),
                    [],
                    await deployer.getAddress(),
                );
                await vaultGovernance.deployVault(
                    anotherTokens.map((token) => token.address),
                    [],
                    await deployer.getAddress(),
                );
                expect(await vaultRegistry.vaults()).to.deep.equal([
                    vault.address,
                    anotherVaultAddress,
                ]);
            });

            // it("reverts when vault is already registered", async () => {
            //     await vaultRegistry.registerVault(vault.address);
            //     await expect(
            //         vaultRegistry.registerVault(vault.address)
            //     ).to.be.revertedWith("Vault already registered");
            // });
    
            // it("throws when vault is not a vault", async () => {
            //     await expect(
            //         vaultRegistry.registerVault(vaultFactory.address)
            //     ).to.be.revertedWith("Vault is not a vault");
            // });
        });

        describe("when called by stranger", async () => {
            it("reverts", async () => {
                await expect(
                    vaultRegistry.registerVault(
                        vaultFactory.address,
                        await stranger.getAddress()
                    )
                ).to.be.revertedWith(Exceptions.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE);
            });
        });

    });

    describe("protocolGovernance", () => {
        it("has correct protocolGovernance", async () => {});
    });

    describe("stagedProtocolGovernance", () => {
        it("has correct stagedProtocolGovernance", async () => {});
    });

    describe("stagedProtocolGovernanceTimestamp", () => {});

    describe("vaultsCount", () => {
        it("has correct vaults count", async () => {

        });
    });

    describe("stageProtocolGovernance", () => {});

    describe("commitStagedProtocolGovernance", () => {});

    describe("commitStagedProtocolGovernance", () => {});
});
