import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Signer } from "ethers";
import {
    ERC20,
    Vault,
    VaultGovernance,
    ProtocolGovernance,
    VaultRegistry,
} from "./library/Types";
import Exceptions from "./library/Exceptions";
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
    let vaultRegistry: VaultRegistry;
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
        console.log("deployer", await deployer.getAddress());
        console.log("admin", await admin.getAddress());
        console.log("treasury", await treasury.getAddress());
        console.log("strategy", await strategy.getAddress());
        console.log("stranger", await stranger.getAddress());
        console.log("anotherTreasury", await anotherTreasury.getAddress());
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
                vaultRegistry,
            } = await deploySubVaultXGatewayVaultSystem({
                adminSigner: admin,
                treasury: await treasury.getAddress(),
                vaultOwnerSigner: deployer,
                strategy: await strategy.getAddress(),
                vaultType: "ERC20Vault",
            }));
            console.log("gatewayVault", gatewayVault.address);
            console.log(
                "gatewayVaultGovernance",
                gatewayVaultGovernance.address
            );
            console.log("vault", vault.address);
            console.log("vaultGovernance", vaultGovernance.address);
            console.log("protocolGovernance", protocolGovernance.address);
            console.log("nft", nft);
            console.log("anotherNft", anotherNft);
            console.log(
                "tokens",
                tokens.map((token) => token.address)
            );
            console.log("anotherVault", anotherVault.address);
            console.log(
                "anotherVaultGovernance",
                anotherVaultGovernance.address
            );
            console.log("vaultRegistry", vaultRegistry.address);
            for (let i: number = 0; i < tokens.length; ++i) {
                await tokens[i].connect(deployer).approve(
                    gatewayVault.address,
                    BigNumber.from(10 ** 9)
                        .mul(BigNumber.from(10 ** 9))
                        .mul(BigNumber.from(10 ** 9))
                );
            }
            await vaultRegistry.approve(await strategy.getAddress(), 3);
            console.log(
                "vaultRegistry.ownerOf(nft)",
                (await vaultRegistry.ownerOf(nft)).toString()
            );
            console.log(
                "vaultRegistry.ownerOf(anotherNft)",
                (await vaultRegistry.ownerOf(anotherNft)).toString()
            );

            console.log("\n\n=== RUNTIME ===\n\n");
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
        it("when called by stranger", async () => {
            await expect(
                vault
                    .connect(stranger)
                    .push(
                        [tokens[0].address],
                        [BigNumber.from(10 ** 9)],
                        false,
                        []
                    )
            ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
        });

        xit("emits Push event", async () => {
            // await tokens[0].connect(deployer).transfer(gatewayVault.address, BigNumber.from(10 ** 9));
            await tokens[0]
                .connect(deployer)
                .transfer(vault.address, BigNumber.from(10 ** 9));
            // await tokens[0].connect(deployer).transfer(anotherVault.address, BigNumber.from(10 ** 9));
            await expect(
                vault
                    .connect(strategy)
                    .push(
                        [tokens[0].address],
                        [BigNumber.from(10 ** 9)],
                        false,
                        []
                    )
            ).to.emit(vault, "Push");
            // await tokens[0].connect(deployer).approve(gatewayVault.address, BigNumber.from(10 ** 9));
            // await vault.connect(strategy).transferAndPush(
            //     await deployer.getAddress(),
            //     [tokens[0].address],
            //     [BigNumber.from(10 ** 9)],
            //     false,
            //     []
            // );

            console.log((await vault.tvl()).toString());
        });
    });

    describe("pull", () => {
        xit("test", async () => {
            await tokens[0]
                .connect(deployer)
                .transfer(vault.address, BigNumber.from(10 ** 9));
            await tokens[1]
                .connect(deployer)
                .transfer(anotherVault.address, BigNumber.from(2 * 10 ** 9));
            // await tokens[0].connect(deployer).transfer(anotherVault.address, BigNumber.from(10 ** 9));
            await expect(
                vault
                    .connect(strategy)
                    .push(
                        [tokens[0].address, tokens[1].address],
                        [BigNumber.from(10 ** 9), BigNumber.from(2 * 10 ** 9)],
                        false,
                        []
                    )
            ).to.emit(vault, "Push");

            await vault
                .connect(strategy)
                .pull(
                    anotherVault.address,
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    false,
                    []
                );
            // await vault
            //     .connect(strategy)
            //     .pull(
            //         anotherVault.address,
            //         [tokens[0].address],
            //         [BigNumber.from(10 ** 9)],
            //         false,
            //         []
            //     );
            console.log((await vault.tvl()).toString());
            console.log((await anotherVault.tvl()).toString());
        });

        it("anotherTest", async () => {
            await tokens[0]
                .connect(deployer)
                .transfer(vault.address, BigNumber.from(10 ** 9));
            await tokens[1]
                .connect(deployer)
                .transfer(vault.address, BigNumber.from(2 * 10 ** 9));
            // await tokens[0].connect(deployer).transfer(anotherVault.address, BigNumber.from(10 ** 9));

            // await expect(
            //     vault
            //         .connect(strategy)
            //         .push(
            //             [tokens[0].address],
            //             [BigNumber.from(10 ** 9)],
            //             false,
            //             []
            //         )
            // ).to.emit(vault, "Push");

            // await expect(
            //     anotherVault
            //         .connect(strategy)
            //         .push(
            //             [tokens[1].address],
            //             [BigNumber.from(2 * 10 ** 9)],
            //             false,
            //             []
            //         )
            // ).to.emit(vault, "Push");

            console.log("vault tvl", (await vault.tvl()).toString());
            console.log(
                "anotherVault tvl",
                (await anotherVault.tvl()).toString()
            );
            console.log(
                "gatewayVault subvaults tvls",
                (await gatewayVault.subvaultsTvl()).toString()
            );

            await expect(
                gatewayVault
                    .connect(strategy)
                    .push(
                        [tokens[0].address, tokens[1].address],
                        [BigNumber.from(10 ** 9), BigNumber.from(2 * 10 ** 9)],
                        false,
                        []
                    )
            ).to.emit(gatewayVault, "Push");

            console.log("vault tvl", (await vault.tvl()).toString());
            console.log(
                "anotherVault tvl",
                (await anotherVault.tvl()).toString()
            );
            console.log(
                "gatewayVault subvaults tvls",
                (await gatewayVault.subvaultsTvl()).toString()
            );

            await gatewayVault
                .connect(deployer)
                .pull(
                    anotherVault.address,
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    false,
                    []
                );

            console.log("vault tvl", (await vault.tvl()).toString());
            console.log(
                "anotherVault tvl",
                (await anotherVault.tvl()).toString()
            );
            console.log(
                "gatewayVault subvaults tvls",
                (await gatewayVault.subvaultsTvl()).toString()
            );
            expect(await vault.tvl()).to.deep.equal([
                BigNumber.from(0),
                BigNumber.from(2 * 10 ** 9),
            ]);
            expect(await gatewayVault.tvl()).to.deep.equal([
                BigNumber.from(10 ** 9),
                BigNumber.from(2 * 10 ** 9),
            ]);
            console.log("earnings", (await vault.earnings()).toString());
            await gatewayVault
                .connect(deployer)
                .collectEarnings(anotherVault.address, []);
            // await vault
            //     .connect(strategy)
            //     .pull(
            //         anotherVault.address,
            //         [tokens[0].address],
            //         [BigNumber.from(10 ** 9)],
            //         false,
            //         []
            //     );
        });
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

    describe("tvl", () => {
        it("when nothing yet pushed", async () => {
            expect(await vault.tvl()).to.deep.equal([
                BigNumber.from(0),
                BigNumber.from(0),
            ]);
        });
    });

    describe("earnings", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty earnings", async () => {
                expect(await gatewayVault.earnings()).to.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
                ]);
            });
        });
    });

    describe("subvaultTvl", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty tvl", async () => {
                expect(await gatewayVault.subvaultTvl(0)).to.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
                ]);
            });
        });
    });

    describe("subvaultsTvl", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty tvl", async () => {
                expect(await gatewayVault.subvaultsTvl()).to.be.deep.equal([
                    [BigNumber.from(0), BigNumber.from(0)],
                    [BigNumber.from(0), BigNumber.from(0)],
                ]);
            });
        });
    });

    describe("vaultEarnings", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty earnings", async () => {
                expect(await gatewayVault.vaultEarnings(0)).to.be.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
                ]);
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

    describe("addSubvaults", () => {
        describe("when called not by VaultGovernance", () => {
            it("reverts", async () => {
                await expect(
                    gatewayVault.connect(strategy).addSubvaults([vault.address])
                ).to.be.revertedWith(
                    Exceptions.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE
                );
            });
        });

        describe("when already initialized", () => {
            it("reverts", async () => {
                ///
            });
        });

        describe("when passed nfts contains zero", () => {});
    });
});
