import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Signer } from "ethers";
import {
    ERC20,
    Vault,
    VaultGovernance,
    ProtocolGovernance,
} from "./library/Types";
import { deploySubVaultXGatewayVaultSystem } from "./library/Deployments";

describe("GatewayVault", () => {
    const tokensCount = 2;
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let strategy: Signer;
    let anotherTreasury: Signer;
    let vaultGovernance: VaultGovernance;
    let anotherVaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vault: Vault;
    let anotherVault: Vault;
    let nft: number;
    let anotherNft: number;
    let tokens: ERC20[];
    let gatewayVault: Vault;
    let gatewayVaultGovernance: VaultGovernance;
    let gatewayNft: number;
    let deployment: Function;

    before(async () => {
        [deployer, admin, stranger, treasury, anotherTreasury, strategy] =
            await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({
                gatewayVault,
                gatewayVaultGovernance,
                vault,
                vaultGovernance,
                protocolGovernance,
                nft,
                anotherNft,
                tokens,
                anotherVault,
                anotherVaultGovernance,
            } = await deploySubVaultXGatewayVaultSystem({
                adminSigner: admin,
                treasury: await treasury.getAddress(),
                vaultOwnerSigner: deployer,
                strategy: await strategy.getAddress(),
                vaultType: "ERC20Vault",
            }));
            for (let i: number = 0; i < tokens.length; ++i) {
                await tokens[i].connect(deployer).approve(
                    gatewayVault.address,
                    BigNumber.from(10 ** 9)
                        .mul(BigNumber.from(10 ** 9))
                        .mul(BigNumber.from(10 ** 9))
                );
            }
        });
    });

    beforeEach(async () => {
        await deployment();
    });

    describe("vaultTokens", () => {
        it("returns correct vault tokens", async () => {
            expect(await vault.vaultTokens()).to.deep.equal(
                tokens.map((token) => token.address)
            );
        });
    });

    describe("push", () => {
        // address
    });

    describe("constructor", () => {
        it("creates GatewayVault", async () => {
            expect(
                await deployer.provider?.getCode(gatewayVault.address)
            ).not.to.be.equal("0x");
        });
    });

    describe("subvaultNfts", () => {
        it("returns nfts", async () => {
            expect(await gatewayVault.subvaultNfts()).to.be.deep.equal([
                nft,
                anotherNft,
            ]);
        });
    });

    describe("tvl", () => {});

    describe("earnings", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty earnings", async () => {
                expect(await gatewayVault.earnings()).to.deep.equal([]);
            });
        });
    });

    describe("subvaultTvl", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty tvl", async () => {
                expect(await gatewayVault.subvaultTvl(0)).to.deep.equal([]);
            });
        });
    });

    describe("subvaultsTvl", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty tvl", async () => {
                expect(await gatewayVault.subvaultsTvl()).to.be.deep.equal([
                    [],
                    [],
                ]);
            });
        });
    });

    describe("vaultEarnings", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty earnings", async () => {
                expect(await gatewayVault.vaultEarnings(0)).to.be.deep.equal(
                    []
                );
            });
        });
    });

    describe("hasSubvault", () => {
        describe("when passed actual vault", () => {
            it("returns true", async () => {
                expect(await gatewayVault.hasSubvault(vault.address)).to.be
                    .true;
                expect(await gatewayVault.hasSubvault(anotherVault.address)).to
                    .be.true;
            });
        });

        describe("when passed not vault", () => {
            it("returns false", async () => {
                expect(
                    await gatewayVault.hasSubvault(await stranger.getAddress())
                ).to.be.false;
            });
        });
    });
});
